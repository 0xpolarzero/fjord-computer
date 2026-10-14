import assert from "node:assert/strict";
import test from "node:test";
import { normalizeGeneratedTypes } from "./generator-transforms.mjs";

test("removes only the duplicate declaration without reading Rust documentation", () => {
  const output = normalizeGeneratedTypes(`// MARK: - SiloWireSiloAP
struct SiloWireSiloAP: Codable { let value: String }
// MARK: - SiloWireInserted
struct SiloWireInserted: Codable { let value: String }
/// Source documentation can change without changing Swift names.
enum SiloWireMacosComputerState: String { case running }
`);

  assert.doesNotMatch(output, /struct SiloWireSiloAP/);
  assert.match(output, /struct SiloWireInserted/);
  assert.match(output, /Source documentation can change/);
});

test("decodes present JSON null as a value for generated terminal result fields", () => {
  const output = normalizeGeneratedTypes(`// MARK: - SiloWireJobFinished
struct SiloWireJobFinished: Codable {
    var jobId: String
    var result: SiloJSONValue? = nil
    enum CodingKeys: String, CodingKey { case jobId = "jobId"; case result = "result" }
}
// MARK: - SiloWireJobOutcome
struct SiloWireJobOutcome: Codable {
    var error: SiloWireErrorObject? = nil
    var result: SiloJSONValue? = nil
    enum CodingKeys: String, CodingKey { case error = "error"; case result = "result" }
}
// MARK: - SiloWireResponseEnvelope
struct SiloWireResponseEnvelope: Codable {
    var id: String
    var result: SiloJSONValue? = nil
    var error: SiloWireErrorObject? = nil
    enum CodingKeys: String, CodingKey { case id = "id"; case result = "result"; case error = "error" }
}
`);

  assert.equal((output.match(/container\.contains\(\.result\)/g) ?? []).length, 3);
  assert.equal((output.match(/container\.decode\(SiloJSONValue\.self, forKey: \.result\)/g) ?? []).length, 3);
});
