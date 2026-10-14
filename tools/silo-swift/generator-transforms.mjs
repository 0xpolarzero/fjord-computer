export function normalizeGeneratedTypes(swiftTypes) {
  let output = swiftTypes.replaceAll("SiloWireSiloAP?", "SiloWirePendingRestore?");
  output = removeDeclaration(output, "SiloWireSiloAP");
  for (const typeName of ["SiloWireJobFinished", "SiloWireJobOutcome", "SiloWireResponseEnvelope"]) {
    output = addPresenceAwareResultDecoder(output, typeName);
  }
  return output;
}

function removeDeclaration(source, typeName) {
  const range = markedDeclarationRange(source, typeName);
  if (!range) return source;
  return source.slice(0, range.markerStart) + source.slice(range.end).replace(/^\n+/, "");
}

function addPresenceAwareResultDecoder(source, typeName) {
  const range = markedDeclarationRange(source, typeName);
  if (!range) return source;
  const beforeCodingKeys = source.slice(range.openBrace + 1, source.indexOf("enum CodingKeys", range.openBrace));
  const properties = [...beforeCodingKeys.matchAll(/^\s*var\s+([A-Za-z_]\w*):\s*([^=\n]+?)(?:\s*=.*)?$/gm)]
    .map((match) => ({ name: match[1], type: match[2].trim() }));
  const result = properties.find(({ name, type }) => name === "result" && type === "SiloJSONValue?");
  if (!result) return source;
  if (source.slice(range.openBrace, range.end).includes("init(from decoder: Decoder)")) return source;

  const assignments = properties.map(({ name, type }) => {
    if (type === "SiloJSONValue?") {
      return `        ${name} = container.contains(.${name}) ? try container.decode(SiloJSONValue.self, forKey: .${name}) : nil`;
    }
    if (type.endsWith("?")) {
      return `        ${name} = try container.decodeIfPresent(${type.slice(0, -1)}.self, forKey: .${name})`;
    }
    return `        ${name} = try container.decode(${type}.self, forKey: .${name})`;
  });
  const initializer = [
    "\n    init(from decoder: Decoder) throws {",
    "        let container = try decoder.container(keyedBy: CodingKeys.self)",
    ...assignments,
    "    }\n",
  ].join("\n");
  const closeBrace = range.end - 1;
  return source.slice(0, closeBrace) + initializer + source.slice(closeBrace);
}

function markedDeclarationRange(source, typeName) {
  const marker = `// MARK: - ${typeName}\n`;
  const markerStart = source.indexOf(marker);
  if (markerStart < 0) return null;
  const declarationPattern = new RegExp(`(?:struct|enum|class)\\s+${escapeRegExp(typeName)}\\b`, "g");
  declarationPattern.lastIndex = markerStart + marker.length;
  const declaration = declarationPattern.exec(source);
  if (!declaration) throw new Error(`quicktype did not emit the marked ${typeName} declaration.`);
  const openBrace = source.indexOf("{", declaration.index + declaration[0].length);
  if (openBrace < 0) throw new Error(`quicktype emitted an unbalanced ${typeName} declaration.`);
  const end = matchingBrace(source, openBrace);
  if (end < 0) throw new Error(`quicktype emitted an unbalanced ${typeName} declaration.`);
  return { markerStart, openBrace, end };
}

function matchingBrace(source, openingBrace) {
  let depth = 0;
  let lineComment = false;
  let blockCommentDepth = 0;
  let inString = false;
  let escaped = false;
  for (let index = openingBrace; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (current === "\n") lineComment = false;
      continue;
    }
    if (blockCommentDepth > 0) {
      if (current === "/" && next === "*") { blockCommentDepth += 1; index += 1; }
      else if (current === "*" && next === "/") { blockCommentDepth -= 1; index += 1; }
      continue;
    }
    if (inString) {
      if (escaped) escaped = false;
      else if (current === "\\") escaped = true;
      else if (current === '"') inString = false;
      continue;
    }
    if (current === "/" && next === "/") { lineComment = true; index += 1; continue; }
    if (current === "/" && next === "*") { blockCommentDepth = 1; index += 1; continue; }
    if (current === '"') { inString = true; continue; }
    if (current === "{") depth += 1;
    else if (current === "}") {
      depth -= 1;
      if (depth === 0) return index + 1;
    }
  }
  return -1;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
