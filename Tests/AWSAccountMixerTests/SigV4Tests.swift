import Foundation
import Testing
@testable import AWSAccountMixer

struct SigV4Tests {
    /// The `get-vanilla` vector from the official AWS SigV4 test suite.
    @Test func matchesAWSTestSuiteGetVanilla() throws {
        let headers = SigV4.authorizationHeaders(
            method: "GET",
            url: URL(string: "https://example.amazonaws.com/")!,
            headers: [:],
            body: Data(),
            credentials: AWSCredentials(accessKeyId: "AKIDEXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
            region: "us-east-1",
            service: "service",
            date: try Date("2015-08-30T12:36:00Z", strategy: .iso8601)
        )
        #expect(headers["X-Amz-Date"] == "20150830T123600Z")
        #expect(headers["Authorization"] == "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
        #expect(headers["X-Amz-Security-Token"] == nil)
    }

    @Test func encodesPlusAndSlashInQuery() {
        #expect(percentEncodedQuery([("Session", "a+b/c=d e")]) == "Session=a%2Bb%2Fc%3Dd%20e")
    }

    @Test func sanitizesFederatedUserName() {
        #expect(ConsoleSignIn.federatedUserName("jane.doe@example") == "jane.doe@example")
        #expect(ConsoleSignIn.federatedUserName("üé") == "aws-account-mixer")
        #expect(ConsoleSignIn.federatedUserName(String(repeating: "x", count: 40)).count == 32)
    }
}
