import Testing
import Foundation
import RevenueCat
@testable import Bond
/// The fleet paywall record, checked in this app's own build.
///
/// The `rc-funnel-probe` run proves an impression reaches RevenueCat. These
/// prove what is underneath it: the counts, the conversion freeze, RevenueCat's
/// silent 40-character key limit, and the rule that nothing here may carry free
/// text or health data. Every assertion is a claim that will be read off a
/// customer record later, so a wrong value is worse than no value.

@MainActor
struct PaywallFunnelTests {

    /// A throwaway suite per test. These counters outlive a launch and would
    /// otherwise carry between tests and into the real container.
    private func withFreshSuite(_ body: () throws -> Void) rethrows {
        let name = "conv.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        ConversionDiagnostics.defaultsOverride = suite
        defer {
            ConversionDiagnostics.defaultsOverride = nil
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        try body()
    }

    @Test func countsPitchesPerSurfaceAndInTotal() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            ConversionDiagnostics.recordPitchView(impressionID: "bond_feature_gate")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["pitch_views_total"] == "3")
            #expect(a["pitch_views_post_onboarding"] == "2")
            #expect(a["pitch_last"] == "feature_gate")
        }
    }

    @Test func noAttributesBeforeAnyPitchIsSeen() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            #expect(ConversionDiagnostics.subscriberAttributes.isEmpty)
        }
    }

    @Test func recordsHowEarlyTheFirstPitchArrived() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["opens_before_first_pitch"] == "2")
            #expect(a["days_since_install"] == "0")
        }
    }

    @Test func theEarlinessPairIsFrozenOnTheFirstPitchOnly() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "bond_feature_gate")
            #expect(ConversionDiagnostics.subscriberAttributes["opens_before_first_pitch"] == "1")
        }
    }

    @Test func anInstallThatPredatesThisCodeReportsNoAge() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["days_since_install"] == nil)
            #expect(a["pitch_views_total"] == "1")
        }
    }

    @Test func conversionFreezesTheSurfaceAndCountAtTheMomentOfSale() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            ConversionDiagnostics.recordPitchView(impressionID: "bond_feature_gate")
            ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true, offeringID: "default")
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["converted_surface"] == "feature_gate")
            #expect(a["pitch_views_at_convert"] == "2")
            #expect(a["converted_with_trial"] == "true")
            #expect(a["converted_offering"] == "default")
        }
    }

    @Test func onlyTheFirstConversionIsRecorded() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: true)
            ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: false)
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["converted_plan"] == "monthly")
            #expect(a["converted_with_trial"] == "true")
        }
    }

    @Test func attributeKeysStayInsideRevenueCatsLimit() throws {
        try withFreshSuite {
            let long = String(repeating: "a", count: 80)
            ConversionDiagnostics.recordPitchView(impressionID: "bond_\(long)")
            for key in ConversionDiagnostics.subscriberAttributes.keys {
                #expect(key.count <= 40, "attribute key too long: \(key)")
            }
        }
    }

    @Test func noAttributeCarriesFreeTextOrHealthData() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "bond_post_onboarding")
            ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)
            for (key, value) in ConversionDiagnostics.subscriberAttributes {
                #expect(!value.contains(" "), "\(key) looks like free text: \(value)")
                #expect(value.count <= 64, "\(key) is too long to be a label")
            }
        }
    }
}

@MainActor
struct PurchaseUXTests {
    private func trialSheet(trialPeriodPhrase: String?, isSolo: Bool) -> TrialOfferSheet {
        TrialOfferSheet(
            isSolo: isSolo, trialPeriodPhrase: trialPeriodPhrase, priceLabel: "$39.99 / year",
            isPurchasing: false, errorMessage: nil,
            onStartTrial: {}, onSeeAllPlans: {}, onDismiss: {}
        )
    }

    @Test func onboardingTrialPromiseRequiresEligibility() {
        #expect(!OnboardingTrialView(name: "Sam").subtitle.contains("free trial"))
        #expect(!OnboardingTrialView(name: "Sam", offersTrial: false).subtitle.contains("free trial"))
        #expect(OnboardingTrialView(name: "Sam", offersTrial: true).subtitle.contains("free trial"))
    }

    @Test func compactOfferDoesNotPromiseFreeAccessWithoutEligibility() {
        for isSolo in [true, false] {
            let sheet = trialSheet(trialPeriodPhrase: nil, isSolo: isSolo)
            #expect(!sheet.subheadline.contains("No payment today"))
            #expect(sheet.billingDisclosure?.contains("trial") == false)
            #expect(sheet.billingDisclosure?.contains("Payment charged") == true)
            let eligible = trialSheet(trialPeriodPhrase: "7 days", isSolo: isSolo)
            #expect(eligible.subheadline.contains("No payment today"))
            #expect(eligible.billingDisclosure?.contains("Free for 7 days") == true)
        }
    }

    @Test func pendingPurchaseWaitsForPremiumAfterRestore() async {
        var restored = false
        let completed = await OnboardingPurchaseRecovery.resolve(
            .pending, isPremium: { false }, restore: { restored = true }
        )
        #expect(restored)
        #expect(!completed)
    }

    @Test func pendingPurchaseCanFinishWhenRestoreUnlocksPremium() async {
        var premium = false
        let completed = await OnboardingPurchaseRecovery.resolve(
            .pending, isPremium: { premium }, restore: { premium = true }
        )
        #expect(completed)
    }

    @Test func cancelledPurchaseNeverFinishesOrRestores() async {
        var restored = false
        let completed = await OnboardingPurchaseRecovery.resolve(
            .cancelled, isPremium: { true }, restore: { restored = true }
        )
        #expect(!completed)
        #expect(!restored)
    }

    @Test func purchasedStillRequiresPremium() async {
        let unresolved = await OnboardingPurchaseRecovery.resolve(
            .purchased, isPremium: { false }, restore: {}
        )
        #expect(!unresolved)
        let completed = await OnboardingPurchaseRecovery.resolve(
            .purchased, isPremium: { true }, restore: {}
        )
        #expect(completed)
    }
}

// MARK: - State machine audit 2026-11-06: B16, "Little Gestures+ since"

struct MemberSinceTests {
    @Test func b16_sinceIsWhenTheSubscriptionBegan_notTheLatestRenewal() {
        let began = Date(timeIntervalSince1970: 1_767_225_600)        // 2026-01-01
        let renewed = Date(timeIntervalSince1970: 1_793_491_200)      // 2026-11-01
        #expect(PurchasesService.memberSince(original: began, latest: renewed) == began)
    }

    @Test func b16_control_withoutAnOriginalDateTheLatestIsAllThereIs() {
        let renewed = Date(timeIntervalSince1970: 1_793_491_200)
        #expect(PurchasesService.memberSince(original: nil, latest: renewed) == renewed)
        #expect(PurchasesService.memberSince(original: nil, latest: nil) == nil)
    }
}

// MARK: - Ask to Buy shows pending

struct AskToBuyOutcomeTests {
    @Test func askToBuyIsWaitingForApprovalNotAFailure() {
        #expect(PurchaseState.outcome(for: .paymentPendingError) == .awaitingApproval)
        // Waiting is distinct from "paid, still syncing" and from an error.
        #expect(PurchaseState.awaitingApproval != .pending)
        #expect(PurchaseState.awaitingApproval.logName == "pending_approval")
        #expect(PurchaseState.pending.logName != PurchaseState.awaitingApproval.logName)
    }

    @Test func aBackedOutSheetIsStillACancel() {
        #expect(PurchaseState.outcome(for: .purchaseCancelledError) == .cancelled)
    }

    @Test func otherErrorsAreNotOutcomes() {
        for code in [ErrorCode.networkError, .offlineConnectionError, .purchaseNotAllowedError,
                     .storeProblemError, .receiptAlreadyInUseError] {
            #expect(PurchaseState.outcome(for: code) == nil)
        }
    }

    @Test func networkErrorsReadAsTheTranslatedConnectionLine() {
        let line = String(localized: "Network issue completing the purchase. Check your connection and try again.")
        #expect(PurchasesService.readablePurchaseError(ErrorCode.networkError) == line)
        #expect(PurchasesService.readablePurchaseError(ErrorCode.offlineConnectionError) == line)
    }

    @Test func otherErrorsKeepTheirCopy() {
        #expect(PurchasesService.readablePurchaseError(ErrorCode.purchaseNotAllowedError)
                == String(localized: "In-app purchases are restricted on this device."))
        #expect(PurchasesService.readablePurchaseError(ErrorCode.productAlreadyPurchasedError)
                == String(localized: "You already own this. Tap Restore to unlock it on this device."))
    }

    @Test func theWaitingCopyIsCalm() {
        let message = PurchaseState.awaitingApprovalMessage
        #expect(message == "Waiting for approval. Your purchase unlocks once it is approved.")
        #expect(!message.lowercased().contains("error"))
        #expect(!message.lowercased().contains("failed"))
        // Even the legacy mapping of the code reads the same, never an error.
        #expect(PurchasesService.readablePurchaseError(ErrorCode.paymentPendingError) == message)
    }

    @MainActor
    @Test func onboardingDoesNotRestoreWhileWaitingForApproval() async {
        var restored = false
        let completed = await OnboardingPurchaseRecovery.resolve(
            .awaitingApproval, isPremium: { true }, restore: { restored = true }
        )
        #expect(!restored)
        #expect(!completed)
    }
}

// MARK: - Remote config: trial_cta and the off switches

@MainActor
struct RemoteConfigTests {
    private let controlOnboarding = String(localized: "Try Little Gestures+ Free")

    @Test func missingNonStringAndUnknownValuesAreControl() {
        #expect(TrialCTA.from(metadata: nil) == .sevenDay)
        #expect(TrialCTA.from(metadata: [:]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": 7]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": true]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "nope"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "MY"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["other": "my"]) == .sevenDay)
    }

    @Test func eachKnownValueIsItsArm() {
        #expect(TrialCTA.from(metadata: ["trial_cta": "seven_day"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "my"]) == .my)
        #expect(TrialCTA.from(metadata: ["trial_cta": "your"]) == .your)
        #expect(TrialCTA.metadataKey == "trial_cta")
        #expect(TrialCTA.allCases.map(\.rawValue) == ["seven_day", "my", "your"])
    }

    @Test func controlIsExactlyTodaysCopyOnEverySurface() {
        // Onboarding, offer sheet and plan screen with a known trial length.
        #expect(TrialCTA.sevenDay.title(trialEligible: true, otherwise: "x") == "Try Little Gestures+ Free")
        #expect(TrialCTA.sevenDay.title(trialEligible: true, otherwise: "x") == controlOnboarding)
        // Plan screen, eligible but StoreKit gave no length.
        #expect(TrialCTA.sevenDay.title(trialEligible: true, lengthKnown: false, otherwise: "x") == "Start Free Trial")
    }

    @Test func eachArmHasItsTitle() {
        for lengthKnown in [true, false] {
            #expect(TrialCTA.my.title(trialEligible: true, lengthKnown: lengthKnown, otherwise: "x") == "Start My Free Trial")
            #expect(TrialCTA.your.title(trialEligible: true, lengthKnown: lengthKnown, otherwise: "x") == "Start Your Free Trial")
        }
    }

    @Test func anIneligibleAccountIsNeverPromisedATrial() {
        for arm in TrialCTA.allCases {
            #expect(arm.title(trialEligible: false, otherwise: "Get Little Gestures+") == "Get Little Gestures+")
            #expect(arm.title(trialEligible: false, lengthKnown: false, otherwise: "Unlock Little Gestures+") == "Unlock Little Gestures+")
        }
    }

    @Test func theOfferSheetFollowsTheArm() {
        func sheet(_ arm: TrialCTA, _ phrase: String?) -> TrialOfferSheet {
            TrialOfferSheet(
                isSolo: true, trialPeriodPhrase: phrase, priceLabel: "$19.99", isPurchasing: false,
                errorMessage: nil, trialCTA: arm, onStartTrial: {}, onSeeAllPlans: {}, onDismiss: {}
            )
        }
        #expect(sheet(.sevenDay, "7 days").ctaTitle == "Try Little Gestures+ Free")
        #expect(sheet(.my, "7 days").ctaTitle == "Start My Free Trial")
        #expect(sheet(.your, "7 days").ctaTitle == "Start Your Free Trial")
        for arm in TrialCTA.allCases {
            #expect(sheet(arm, nil).ctaTitle == "Unlock Little Gestures+")
        }
    }

    @Test func theSwitchIsOnUnlessTheValueIsOff() {
        let key = "rating_prompt"
        #expect(RemoteConfig.isOn(.ratingPrompt, in: nil))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [key: "on"]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [key: false]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [key: "OFF"]))
        #expect(!RemoteConfig.isOn(.ratingPrompt, in: [key: "off"]))
        #expect(RemoteSwitch.ratingPrompt.rawValue == key)
    }
}
