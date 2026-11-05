import Foundation
import RevenueCat

enum BondPackageKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension BondPackageKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier]
                .map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains("lifetime") }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains("yearly") || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains("monthly") }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var bondPackageKind: BondPackageKind { BondPackageKind(package: self) }

    var bondDisplayName: String {
        switch bondPackageKind {
        case .lifetime: return String(localized: "Lifetime")
        case .yearly:   return String(localized: "Yearly")
        case .monthly:  return String(localized: "Monthly")
        case .other:    return storeProduct.localizedTitle
        }
    }

    var bondPriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else {
            return storeProduct.localizedPriceString
        }
        let price = storeProduct.localizedPriceString
        if period.value == 1 {
            switch period.unit {
            case .day:   return String(localized: "\(price) / day")
            case .week:  return String(localized: "\(price) / week")
            case .month: return String(localized: "\(price) / month")
            case .year:  return String(localized: "\(price) / year")
            @unknown default: return price
            }
        }
        let length = Self.durationPhrase(period.value, period.unit)
        return String(localized: "\(price) / \(length)")
    }

    /// "3 months", "2 weeks": a duration through Foundation, never spliced
    /// from a number and a hand-pluralised unit.
    static func durationPhrase(_ value: Int, _ unit: SubscriptionPeriod.Unit) -> String {
        var components = DateComponents()
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        switch unit {
        case .day:   components.day = value;        formatter.allowedUnits = [.day]
        case .week:  components.weekOfMonth = value; formatter.allowedUnits = [.weekOfMonth]
        case .month: components.month = value;      formatter.allowedUnits = [.month]
        case .year:  components.year = value;       formatter.allowedUnits = [.year]
        @unknown default: return ""
        }
        return formatter.string(from: components) ?? ""
    }

    /// Free-trial length as a phrase ("7 days", "1 month"), nil without a trial.
    var bondTrialPeriodPhrase: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        if period.unit == .week {
            return Self.durationPhrase(period.value * 7, .day)
        }
        return Self.durationPhrase(period.value, period.unit)
    }

    var bondIntroOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day:   return String(localized: "\(period.value)-day free trial")
        case .week:  return String(localized: "\(period.value * 7)-day free trial")
        case .month: return String(localized: "\(period.value)-month free trial")
        case .year:  return String(localized: "\(period.value)-year free trial")
        @unknown default: return nil
        }
    }

    /// Title-cased variant of `bondIntroOfferLabel` for the plan-card badge
    /// ("7-Day Free Trial"). Its own keys, so no translated text is capitalized.
    var bondIntroOfferBadge: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day:   return String(localized: "\(period.value)-Day Free Trial")
        case .week:  return String(localized: "\(period.value * 7)-Day Free Trial")
        case .month: return String(localized: "\(period.value)-Month Free Trial")
        case .year:  return String(localized: "\(period.value)-Year Free Trial")
        @unknown default: return nil
        }
    }

    /// Trial length in days, if the package has a free-trial intro offer.
    var bondTrialDays: Int? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day:   return period.value
        case .week:  return period.value * 7
        case .month: return period.value * 30
        case .year:  return period.value * 365
        @unknown default: return nil
        }
    }

    /// Localized per-week price string (e.g. "$0.96/wk"), derived from the
    /// subscription period. Returns nil for one-shot products.
    var bondPricePerWeekLabel: String? {
        guard let period = storeProduct.subscriptionPeriod else { return nil }
        let weeks: Decimal
        switch period.unit {
        case .day:   weeks = Decimal(period.value) / 7
        case .week:  weeks = Decimal(period.value)
        case .month: weeks = Decimal(period.value) * Decimal(string: "4.345")!
        case .year:  weeks = Decimal(period.value) * 52
        @unknown default: return nil
        }
        guard weeks > 0 else { return nil }
        let perWeek = storeProduct.price / weeks
        return String(localized: "\(formatted(price: perWeek))/wk")
    }

    /// Approximate monthly price for this package (used for savings math).
    var bondMonthlyPriceValue: Decimal? {
        guard let period = storeProduct.subscriptionPeriod else { return nil }
        let months: Decimal
        switch period.unit {
        case .day:   months = Decimal(period.value) / 30
        case .week:  months = Decimal(period.value) / Decimal(string: "4.345")!
        case .month: months = Decimal(period.value)
        case .year:  months = Decimal(period.value) * 12
        @unknown default: return nil
        }
        guard months > 0 else { return nil }
        return storeProduct.price / months
    }

    /// Percent savings vs the supplied monthly package, e.g. 60 for "Save 60%".
    /// Returns nil if either side lacks a usable monthly equivalent or savings ≤ 0.
    func bondSavingsPercent(comparedToMonthly monthly: Package) -> Int? {
        guard
            let mine = bondMonthlyPriceValue,
            let other = monthly.bondMonthlyPriceValue,
            other > 0,
            mine < other
        else { return nil }
        let ratio = (other - mine) / other
        let percent = NSDecimalNumber(decimal: ratio * 100).doubleValue
        let rounded = Int(percent.rounded())
        return rounded > 0 ? rounded : nil
    }

    private func formatted(price: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = storeProduct.priceFormatter?.locale ?? .current
        if let currencyCode = storeProduct.currencyCode {
            formatter.currencyCode = currencyCode
        }
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: price))
            ?? storeProduct.localizedPriceString
    }
}

extension Offering {
    var bondSortedPackages: [Package] {
        availablePackages.sorted {
            let lhs = $0.bondPackageKind
            let rhs = $1.bondPackageKind
            if lhs.rawValue != rhs.rawValue { return lhs.rawValue < rhs.rawValue }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    var bondPaywallOffering: Offering? {
        offering(identifier: "default") ?? current
    }
}
