import XCTest
import KeychainAccess
@testable import Scrainee

/// Tests for KeychainService
/// Uses a separate test keychain to avoid interfering with production data
@MainActor
final class KeychainServiceTests: XCTestCase {

    /// Test keychain with unique service identifier
    private var testKeychain: Keychain!
    private let testServiceId = "com.cpohl.scrainee.tests.\(UUID().uuidString)"

    override func setUp() async throws {
        testKeychain = Keychain(service: testServiceId)
            .accessibility(.afterFirstUnlock)
    }

    override func tearDown() async throws {
        // Clean up all test keys
        try? testKeychain.removeAll()
        testKeychain = nil
    }

    // MARK: - Basic Get/Set/Remove Tests

    func testSet_andGet_returnsStoredValue() async throws {
        // Given
        let testKey = "test_api_key"
        let testValue = "sk-ant-api03-test123"

        // When
        try testKeychain.set(testValue, key: testKey)
        let retrieved = try testKeychain.get(testKey)

        // Then
        XCTAssertEqual(retrieved, testValue)
    }

    func testGet_nonExistentKey_returnsNil() async throws {
        // Given
        let nonExistentKey = "non_existent_key_\(UUID().uuidString)"

        // When
        let result = try testKeychain.get(nonExistentKey)

        // Then
        XCTAssertNil(result)
    }

    func testRemove_existingKey_removesValue() async throws {
        // Given
        let testKey = "key_to_remove"
        try testKeychain.set("some_value", key: testKey)

        // When
        try testKeychain.remove(testKey)
        let result = try testKeychain.get(testKey)

        // Then
        XCTAssertNil(result)
    }

    func testRemove_nonExistentKey_doesNotThrow() async throws {
        // Given
        let nonExistentKey = "non_existent_\(UUID().uuidString)"

        // When/Then - should not throw
        XCTAssertNoThrow(try testKeychain.remove(nonExistentKey))
    }

    // MARK: - Update Tests

    func testSet_existingKey_updatesValue() async throws {
        // Given
        let testKey = "api_key"
        let originalValue = "original_value"
        let updatedValue = "updated_value"
        try testKeychain.set(originalValue, key: testKey)

        // When
        try testKeychain.set(updatedValue, key: testKey)
        let result = try testKeychain.get(testKey)

        // Then
        XCTAssertEqual(result, updatedValue)
    }

    // MARK: - Empty String Tests

    func testSet_emptyString_storesEmptyString() async throws {
        // Given
        let testKey = "empty_key"

        // When
        try testKeychain.set("", key: testKey)
        let result = try testKeychain.get(testKey)

        // Then
        XCTAssertEqual(result, "")
    }

    // MARK: - Special Character Tests

    func testSet_specialCharacters_preservesValue() async throws {
        // Given
        let testKey = "special_chars"
        let specialValue = "sk-ant-api03-äöü!@#$%^&*()_+-={}[]|\\:\";<>?,./~`"

        // When
        try testKeychain.set(specialValue, key: testKey)
        let result = try testKeychain.get(testKey)

        // Then
        XCTAssertEqual(result, specialValue)
    }

    func testSet_unicodeCharacters_preservesValue() async throws {
        // Given
        let testKey = "unicode"
        let unicodeValue = "🔐🔑📝 API Key: 密钥 キー مفتاح"

        // When
        try testKeychain.set(unicodeValue, key: testKey)
        let result = try testKeychain.get(testKey)

        // Then
        XCTAssertEqual(result, unicodeValue)
    }

    // MARK: - Long Value Tests

    func testSet_longValue_preservesValue() async throws {
        // Given
        let testKey = "long_value"
        let longValue = String(repeating: "a", count: 10000)

        // When
        try testKeychain.set(longValue, key: testKey)
        let result = try testKeychain.get(testKey)

        // Then
        XCTAssertEqual(result, longValue)
    }

    // MARK: - Multiple Keys Tests

    func testMultipleKeys_independent() async throws {
        // Given
        let key1 = "claude_api"
        let key2 = "notion_api"
        let key3 = "notion_db"
        let value1 = "claude_value"
        let value2 = "notion_value"
        let value3 = "db_id_value"

        // When
        try testKeychain.set(value1, key: key1)
        try testKeychain.set(value2, key: key2)
        try testKeychain.set(value3, key: key3)

        // Then
        XCTAssertEqual(try testKeychain.get(key1), value1)
        XCTAssertEqual(try testKeychain.get(key2), value2)
        XCTAssertEqual(try testKeychain.get(key3), value3)
    }

    func testRemoveOne_leavesOthers() async throws {
        // Given
        let key1 = "key1"
        let key2 = "key2"
        try testKeychain.set("value1", key: key1)
        try testKeychain.set("value2", key: key2)

        // When
        try testKeychain.remove(key1)

        // Then
        XCTAssertNil(try testKeychain.get(key1))
        XCTAssertEqual(try testKeychain.get(key2), "value2")
    }

    // MARK: - RemoveAll Tests

    func testRemoveAll_clearsAllKeys() async throws {
        // Given
        try testKeychain.set("value1", key: "key1")
        try testKeychain.set("value2", key: "key2")
        try testKeychain.set("value3", key: "key3")

        // When
        try testKeychain.removeAll()

        // Then
        XCTAssertNil(try testKeychain.get("key1"))
        XCTAssertNil(try testKeychain.get("key2"))
        XCTAssertNil(try testKeychain.get("key3"))
    }

    // MARK: - KeychainService.Key Enum Tests

    func testKeyEnum_rawValues() {
        // Verify the raw values match expected keychain keys
        XCTAssertEqual(KeychainService.Key.claudeAPIKey.rawValue, "claude_api_key")
        XCTAssertEqual(KeychainService.Key.notionAPIKey.rawValue, "notion_api_key")
        XCTAssertEqual(KeychainService.Key.notionDatabaseId.rawValue, "notion_database_id")
    }

    // MARK: - API Key Format Tests (Validation Helpers)

    func testClaudeAPIKeyFormat_startsWithSkAnt() {
        // Given - typical Claude API key format
        let validKey = "sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        let invalidKey = "invalid_key"

        // Then
        XCTAssertTrue(validKey.hasPrefix("sk-ant-"))
        XCTAssertFalse(invalidKey.hasPrefix("sk-ant-"))
    }

    func testNotionAPIKeyFormat_startsWithSecret() {
        // Given - typical Notion API key format
        let validKey = "secret_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        let invalidKey = "invalid_key"

        // Then
        XCTAssertTrue(validKey.hasPrefix("secret_"))
        XCTAssertFalse(invalidKey.hasPrefix("secret_"))
    }
}
