import Foundation
import Testing
@testable import SpeedRead

@Suite("OPDS server form logic")
struct OPDSServerFormLogicTests {
    @Test func saveEligibilityRequiresBothNonWhitespaceFields() {
        #expect(!OPDSServerFormLogic.canSave(name: "", urlString: "books.example"))
        #expect(!OPDSServerFormLogic.canSave(name: "Library", urlString: "   "))
        #expect(OPDSServerFormLogic.canSave(name: " Library ", urlString: "books.example"))
    }

    @Test func validationTrimsAndDefaultsAHostToHTTPS() {
        #expect(OPDSServerFormLogic.validateURL(
            "  books.example.com/opds  ",
            allowInsecureHTTP: false
        ) == .valid(URL(string: "https://books.example.com/opds")!))
    }

    @Test func validationRejectsMalformedAndDisallowedPlainHTTP() {
        #expect(OPDSServerFormLogic.validateURL(
            "https://",
            allowInsecureHTTP: false
        ) == .invalid)
        #expect(OPDSServerFormLogic.validateURL(
            "HTTP://books.example/opds",
            allowInsecureHTTP: false
        ) == .insecureHTTP)
        #expect(OPDSServerFormLogic.validateURL(
            "http://books.example/opds",
            allowInsecureHTTP: true
        ) == .valid(URL(string: "http://books.example/opds")!))
    }

    @Test func displayWarningRecognizesTheTypedSchemeCaseInsensitively() {
        #expect(OPDSServerFormLogic.isPendingPlainHTTP("HTTP://books.example"))
        #expect(!OPDSServerFormLogic.isPendingPlainHTTP("https://books.example"))
        #expect(!OPDSServerFormLogic.isPendingPlainHTTP(" http://books.example"))
    }

    @Test func persistedIdentityFieldsAreTrimmedWithoutTouchingPasswords() {
        #expect(OPDSServerFormLogic.normalizedIdentity(
            name: " Home ",
            username: " reader ",
            password: " secret with spaces "
        ) == .init(
            name: "Home",
            username: "reader",
            password: " secret with spaces "
        ))
    }
}
