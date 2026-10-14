import { readFile, writeFile } from "node:fs/promises";
import { InputData, JSONSchemaInput, Ref, quicktype } from "quicktype-core";
import { SiloSwiftTargetLanguage, siloSchemaAttributeProducer } from "./swift-renderer.mjs";

const [schemaPath, outputPath, methodsPath] = process.argv.slice(2);
if (!schemaPath || !outputPath || !methodsPath) {
  throw new Error("Usage: node generate.mjs <schema.json> <types.swift> <methods.swift>");
}

const schema = JSON.parse(await readFile(schemaPath, "utf8"));
if (schema.$schema !== "https://json-schema.org/draft/2020-12/schema") {
  throw new Error(`Unsupported JSON Schema dialect: ${schema.$schema ?? "missing"}`);
}
if (!Array.isArray(schema["x-silo-methods"]) || !Array.isArray(schema["x-silo-job-results"])) {
  throw new Error("Schema is missing Silo method and job result metadata.");
}
const integerFormats = new Set(["uint8", "uint16", "uint32", "uint64", "uint", "int32", "int64"]);
const unsupportedIntegers = [];
function validateIntegerFormats(value, pointer = "") {
  if (Array.isArray(value)) {
    value.forEach((child, index) => validateIntegerFormats(child, `${pointer}/${index}`));
    return;
  }
  if (!value || typeof value !== "object") return;
  const type = value.type;
  const integer = type === "integer" || (Array.isArray(type) && type.includes("integer"));
  if (integer && !integerFormats.has(value.format) && pointer !== "/$defs/DisplayAxis") {
    unsupportedIntegers.push(`${pointer || "/"} (${value.format ?? "no format"})`);
  }
  for (const [key, child] of Object.entries(value)) validateIntegerFormats(child, `${pointer}/${key}`);
}
validateIntegerFormats(schema);
if (unsupportedIntegers.length > 0) {
  throw new Error(`Unsupported integer schema fields:\n${unsupportedIntegers.join("\n")}`);
}
const methods = schema["x-silo-methods"];
const methodNames = new Set(methods.map((method) => method.name));
if (methodNames.size !== methods.length) throw new Error("Duplicate canonical method name in schema metadata.");
const definitionNames = new Set(Object.keys(schema.$defs ?? {}));
function unionSchemasByMethod(definitionName, payloadKey) {
  const definition = schema.$defs[definitionName];
  if (!Array.isArray(definition?.oneOf)) throw new Error(`Schema is missing ${definitionName}.oneOf.`);
  const values = new Map();
  for (const variant of definition.oneOf) {
    const name = variant?.properties?.method?.const;
    const payload = variant?.properties?.[payloadKey];
    if (typeof name !== "string" || payload === undefined) throw new Error(`Malformed ${definitionName} variant.`);
    if (values.has(name)) throw new Error(`Duplicate ${definitionName} variant ${name}.`);
    values.set(name, payload);
  }
  return values;
}
const methodParams = unionSchemasByMethod("MethodParams", "params");
const methodResults = unionSchemasByMethod("MethodResults", "result");
function swiftTypeForSchema(value) {
  if (value === true) return "SiloJSONValue";
  if (value === false || !value || typeof value !== "object") throw new Error(`Unsupported method schema shape: ${JSON.stringify(value)}`);
  if (value.$ref) {
    const definitionName = value.$ref.match(/^#\/\$defs\/([^/]+)$/)?.[1];
    if (!definitionName || !definitionNames.has(definitionName)) throw new Error(`Unsupported schema reference ${value.$ref}`);
    return `SiloWire${definitionName}`;
  }
  if (Array.isArray(value.anyOf) || Array.isArray(value.oneOf)) {
    const variants = value.anyOf ?? value.oneOf;
    const nonNull = variants.filter((variant) => variant?.type !== "null");
    if (nonNull.length === 1 && nonNull.length !== variants.length) return `${swiftTypeForSchema(nonNull[0])}?`;
    if (nonNull.length === 1) return swiftTypeForSchema(nonNull[0]);
    return "SiloJSONValue";
  }
  const type = value.type;
  if (Array.isArray(type)) {
    const nonNull = type.filter((member) => member !== "null");
    if (nonNull.length === 1 && nonNull.length !== type.length) return `${swiftTypeForSchema({ ...value, type: nonNull[0] })}?`;
    if (nonNull.length === 1) return swiftTypeForSchema({ ...value, type: nonNull[0] });
  }
  if (type === "null") return "SiloNull";
  if (type === "array") return `[${swiftTypeForSchema(value.items)}]`;
  if (type === "string") return "String";
  if (type === "boolean") return "Bool";
  if (type === "number") return "Double";
  if (type === "integer") {
    if (value.format === "uint64") return "UInt64";
    if (value.format === "int64") return "Int64";
    if (value.format === "int32") return "Int32";
    if (!value.format && value.minimum === 0 && value.maximum === 32767) return "SiloDisplayAxis";
    if (["uint8", "uint16", "uint32", "uint"].includes(value.format)) return "Int";
    throw new Error(`Unsupported method integer schema: ${JSON.stringify(value)}`);
  }
  if (type === "object") return "SiloJSONValue";
  throw new Error(`Unsupported method schema type: ${JSON.stringify(value)}`);
}
for (const method of methods) {
  if (!methodParams.has(method.name) || !methodResults.has(method.name)) {
    throw new Error(`Method contract schema is missing params/results for ${method.name}.`);
  }
}
const schemaInput = new JSONSchemaInput(undefined, [siloSchemaAttributeProducer]);
schemaInput.addSourceSync({ name: "SiloAPI", schema: JSON.stringify(schema) });
for (const definitionName of [...definitionNames].sort()) {
  schemaInput.addTopLevel(definitionName, Ref.parse(`SiloAPI#/$defs/${definitionName}`));
}
const inputData = new InputData();
inputData.addInput(schemaInput);

const result = await quicktype({
  inputData,
  lang: new SiloSwiftTargetLanguage(),
  rendererOptions: {
    "access-level": "internal",
    "acronym-style": "original",
    "coding-keys": true,
    "initializers": false,
    "mutable-properties": true,
    protocol: "equatable",
    "sendable": true,
    "type-prefix": "SiloWire",
  },
  outputFilename: "SiloAPI.swift",
});
// quicktype emits Codable properties but no memberwise initializer. Giving schema-optional
// fields a nil default keeps the generated models usable as mutable client projections
// without changing their JSON decoding or omission behavior.
let swiftTypes = `${result.lines.join("\n")}\n`.replace(
  /^(\s+var [A-Za-z_]\w*: .+\?)$/gm,
  "$1 = nil",
);
// quicktype emits this duplicate shape name for the schema's untagged PendingRestore
// anyOf. Route references through the actual named definition and remove the duplicate.
swiftTypes = swiftTypes.replaceAll("SiloWireSiloAP?", "SiloWirePendingRestore?");
const duplicatePendingRestore = swiftTypes.indexOf("// MARK: - SiloWireSiloAP\n");
if (duplicatePendingRestore >= 0) {
  const nextDefinition = swiftTypes.indexOf(
    "/// Mirrors `app/SiloUI/src-tauri/src/macos_computers/store.rs::State`.",
    duplicatePendingRestore,
  );
  if (nextDefinition < 0) throw new Error("quicktype's duplicate PendingRestore shape was not followed by MacosComputerState.");
  swiftTypes = swiftTypes.slice(0, duplicatePendingRestore) + swiftTypes.slice(nextDefinition);
}
await writeFile(outputPath, swiftTypes);

const kinds = [...new Set(methods.map((method) => method.kind))].sort();
const swiftMethodName = (name) => name.split(".").map((part, index) => {
  const word = part.replace(/[^A-Za-z0-9_]/g, "_");
  if (index === 0) return word[0].toLowerCase() + word.slice(1);
  return word[0].toUpperCase() + word.slice(1);
}).join("");
const methodFunctions = methods.map((method) => {
  const paramsType = swiftTypeForSchema(methodParams.get(method.name));
  const resultType = swiftTypeForSchema(methodResults.get(method.name));
  return `    static func ${swiftMethodName(method.name)}(_ params: ${paramsType}) -> SiloGeneratedMethodCall<${paramsType}, ${resultType}> {\n` +
    `        SiloGeneratedMethodCall<${paramsType}, ${resultType}>(name: "${method.name}", kind: .${method.kind}, params: params)\n    }`;
});
const methodCatalog = methods.map((method) =>
  `        SiloGeneratedMethodDescriptor(name: "${method.name}", kind: .${method.kind}, paramsType: "${method.paramsType}", resultType: "${method.resultType}")`,
);
const methodsSource = `// This file is generated from JSON Schema metadata using quicktype-core, do not modify it directly.\nimport Foundation\n\nenum SiloGeneratedMethodKind: String, Codable, Sendable {\n${kinds.map((kind) => `    case ${kind}`).join("\n")}\n}\n\nstruct SiloGeneratedMethodDescriptor: Equatable, Sendable {\n    let name: String\n    let kind: SiloGeneratedMethodKind\n    let paramsType: String\n    let resultType: String\n}\n\nstruct SiloGeneratedMethodCall<Params: Encodable & Sendable, Result: Decodable & Sendable>: Sendable {\n    let name: String\n    let kind: SiloGeneratedMethodKind\n    let params: Params\n}\n\nenum SiloGeneratedMethods {\n    static let all: [SiloGeneratedMethodDescriptor] = [\n${methodCatalog.join(",\n")}\n    ]\n\n${methodFunctions.join("\n\n")}\n}\n`;
await writeFile(methodsPath, methodsSource);
