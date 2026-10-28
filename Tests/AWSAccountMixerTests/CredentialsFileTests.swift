import Foundation
import Testing
@testable import AWSAccountMixer

struct CredentialsFileTests {
    @Test func parsesSectionsCommentsAndWhitespace() {
        let sections = CredentialsFile.parse("""
        # comment
        [default]
        aws_access_key_id = AKIA1
          aws_secret_access_key=secret=with=equals

        ; another comment
        [ prod ]
        AWS_ACCESS_KEY_ID = AKIA2
        """)
        #expect(sections.map(\.name) == ["default", "prod"])
        #expect(sections[0].values["aws_secret_access_key"] == "secret=with=equals")
        #expect(sections[1].values["aws_access_key_id"] == "AKIA2")
    }

    @Test func mergesDuplicateKeysAndSuggestsNames() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try """
        [default]
        aws_access_key_id = AKIASHARED
        aws_secret_access_key = s1
        [acme-prod]
        aws_access_key_id = AKIAPROD
        aws_secret_access_key = s2
        [temporary]
        aws_access_key_id = ASIATEMP
        aws_secret_access_key = s3
        aws_session_token = token
        """.write(to: directory.appending(path: "credentials"), atomically: true, encoding: .utf8)
        try """
        [default]
        aws_access_key_id = AKIASHARED
        aws_secret_access_key = s1
        """.write(to: directory.appending(path: "credentials.staging"), atomically: true, encoding: .utf8)
        try "ignored".write(to: directory.appending(path: "config"), atomically: true, encoding: .utf8)

        let profiles = CredentialsFile.scan(directory: directory)
        #expect(profiles.map(\.accessKeyId) == ["AKIASHARED", "AKIAPROD"])
        #expect(profiles[0].sources.count == 2)
        #expect(profiles[0].suggestedName == "staging")
        #expect(profiles[1].suggestedName == "acme-prod")
    }

    @Test func normalizesAccountIds() {
        #expect("1234-5678-9012".normalizedAccountId == "123456789012")
        #expect(" my-alias ".normalizedAccountId == "my-alias")
    }
}

struct RegionTests {
    @Test func fallsBackToDefaultRegion() {
        var account = Account(name: "Dev", accountId: "123456789012")
        #expect(account.effectiveRegion(default: "eu-central-1") == "eu-central-1")
        #expect(account.effectiveRegion(default: "").isEmpty)
        #expect(ConsoleService.home.url(region: account.effectiveRegion(default: "eu-central-1")).absoluteString
            == "https://console.aws.amazon.com/console/home?region=eu-central-1")

        account.region = "us-east-1"
        #expect(account.effectiveRegion(default: "eu-central-1") == "us-east-1")
        #expect(account.subtitle(defaultRegion: "eu-central-1") == "1234-5678-9012 · us-east-1")
    }
}
