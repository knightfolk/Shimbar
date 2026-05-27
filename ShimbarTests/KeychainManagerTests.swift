import XCTest
@testable import Shimbar

final class KeychainManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clean up test provider keys before each test
        try? KeychainManager.deleteKey(forProvider: "test-provider")
    }
    
    override func tearDown() {
        try? KeychainManager.deleteKey(forProvider: "test-provider")
        super.tearDown()
    }
    
    func testKeychainSaveAndGet() {
        let testKey = "sk-test123456"
        let provider = "test-provider"
        
        XCTAssertNoThrow(try KeychainManager.saveKey(testKey, forProvider: provider))
        
        let retrieved = KeychainManager.getKey(forProvider: provider)
        XCTAssertEqual(retrieved, testKey)
    }
    
    func testKeychainDelete() {
        let testKey = "sk-test-delete"
        let provider = "test-provider"
        
        XCTAssertNoThrow(try KeychainManager.saveKey(testKey, forProvider: provider))
        XCTAssertNoThrow(try KeychainManager.deleteKey(forProvider: provider))
        
        let retrieved = KeychainManager.getKey(forProvider: provider)
        XCTAssertNil(retrieved)
    }
    
    func testStoredProviderIds() {
        let testKey = "sk-test-stored-ids"
        let provider = "test-provider"
        
        XCTAssertNoThrow(try KeychainManager.saveKey(testKey, forProvider: provider))
        
        let stored = KeychainManager.storedProviderIds()
        XCTAssertTrue(stored.contains(provider), "Stored providers should contain our test provider")
    }
}
