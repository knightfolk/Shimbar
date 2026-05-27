import XCTest
@testable import Shimbar

final class ApiKeyValidatorTests: XCTestCase {
    
    func testValidationResultOutcomes() {
        let validResult = ValidationResult.valid(models: ["model1", "model2"])
        let invalidResult = ValidationResult.invalid(reason: "Wrong key")
        let errorResult = ValidationResult.networkError("Host unreachable")
        
        if case .valid(let models) = validResult {
            XCTAssertEqual(models.count, 2)
            XCTAssertEqual(models.first, "model1")
        } else {
            XCTFail("Outcome should match valid case")
        }
        
        if case .invalid(let reason) = invalidResult {
            XCTAssertEqual(reason, "Wrong key")
        } else {
            XCTFail("Outcome should match invalid case")
        }
        
        if case .networkError(let err) = errorResult {
            XCTAssertEqual(err, "Host unreachable")
        } else {
            XCTFail("Outcome should match networkError case")
        }
    }
}
