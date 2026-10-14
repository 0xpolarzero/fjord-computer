import {
  SwiftRenderer,
  SwiftTargetLanguage,
  TypeAttributeKind,
  getOptionValues,
  swiftOptions,
} from "quicktype-core";

const formats = new Set(["uint8", "uint16", "uint32", "uint64", "uint", "int32", "int64", "display-axis"]);

class SiloIntegerFormat extends TypeAttributeKind {
  constructor() {
    super("siloIntegerFormat");
  }

  get inIdentity() {
    return true;
  }

  appliesToTypeKind(kind) {
    return kind === "integer";
  }

  combine(values) {
    return values.every((value) => value === values[0]) ? values[0] : undefined;
  }

  intersect(values) {
    return values.every((value) => value === values[0]) ? values[0] : undefined;
  }

  makeInferred(value) {
    return value;
  }

  stringify(value) {
    return value;
  }
}

export const siloIntegerFormat = new SiloIntegerFormat();

export function siloSchemaAttributeProducer(schema, canonicalRef, types) {
  if (!types.has("integer")) return undefined;
  let format = schema.format;
  if (!format && schema.minimum === 0 && schema.maximum === 32767) format = "display-axis";
  if (!format || !formats.has(format)) return undefined;
  return { forNumber: siloIntegerFormat.makeAttributes(format) };
}

class SiloSwiftRenderer extends SwiftRenderer {
  swiftType(type, withIssues = false, noOptional = false) {
    if (type.kind === "any" || type.kind === "null") return "SiloJSONValue";
    if (type.kind === "integer") {
      const format = siloIntegerFormat.tryGetInAttributes(type.getAttributes());
      const swiftType = {
        uint8: "Int",
        uint16: "Int",
        uint32: "Int",
        uint: "Int",
        uint64: "UInt64",
        int32: "Int32",
        int64: "Int64",
        "display-axis": "SiloDisplayAxis",
      }[format];
      if (!swiftType) throw new Error(`Unsupported Silo integer representation for ${type.getCombinedName()}: ${format ?? "missing schema format"}`);
      return swiftType;
    }
    return super.swiftType(type, withIssues, noOptional);
  }
}

export class SiloSwiftTargetLanguage extends SwiftTargetLanguage {
  makeRenderer(renderContext, optionValues) {
    return new SiloSwiftRenderer(this, renderContext, getOptionValues(swiftOptions, optionValues));
  }
}

export function swiftTypeForRust(typeName, definitionNames) {
  const type = typeName.trim();
  if (type === "()") return "SiloNull";
  if (type === "String") return "String";
  if (type === "bool") return "Bool";
  if (type.startsWith("Vec<") && type.endsWith(">")) {
    return `[${swiftTypeForRust(type.slice(4, -1), definitionNames)}]`;
  }
  if (type.startsWith("Option<") && type.endsWith(">")) {
    return `${swiftTypeForRust(type.slice(7, -1), definitionNames)}?`;
  }
  const definitionName = type.split("::").at(-1);
  if (definitionNames.has(definitionName)) return `SiloWire${definitionName}`;
  throw new Error(`No schema definition for method type ${JSON.stringify(typeName)}`);
}
