import Foundation

enum AutomationOverviewExampleScenario: String, CaseIterable, Identifiable {
    case executiveBriefing
    case campaignReview
    case productOpportunity
    case multiProviderReview

    var id: Self { self }

    var title: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveTitle
        case .campaignReview:
            AppStrings.Automation.exampleCampaignTitle
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityTitle
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderTitle
        }
    }

    var summary: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveSummary
        case .campaignReview:
            AppStrings.Automation.exampleCampaignSummary
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunitySummary
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderSummary
        }
    }

    var workSkill: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveWorkSkill
        case .campaignReview:
            AppStrings.Automation.exampleCampaignWorkSkill
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityWorkSkill
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderWorkSkill
        }
    }

    var reviewSkill: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveReviewSkill
        case .campaignReview:
            AppStrings.Automation.exampleCampaignReviewSkill
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityReviewSkill
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderReviewSkill
        }
    }

    var workSkillImage: String {
        switch self {
        case .executiveBriefing:
            "chart.line.uptrend.xyaxis"
        case .campaignReview:
            "chart.bar.fill"
        case .productOpportunity:
            "binoculars.fill"
        case .multiProviderReview:
            "square.and.pencil"
        }
    }

    var reviewSkillImage: String {
        switch self {
        case .executiveBriefing:
            "doc.text.fill"
        case .campaignReview:
            "checkmark.seal.fill"
        case .productOpportunity:
            "lightbulb.fill"
        case .multiProviderReview:
            "person.2.fill"
        }
    }

    var firstVibe: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveFirstVibe
        case .campaignReview:
            AppStrings.Automation.exampleCampaignFirstVibe
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityFirstVibe
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderFirstVibe
        }
    }

    var secondVibe: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveSecondVibe
        case .campaignReview:
            AppStrings.Automation.exampleCampaignSecondVibe
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunitySecondVibe
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderSecondVibe
        }
    }

    var thirdVibe: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveThirdVibe
        case .campaignReview:
            AppStrings.Automation.exampleCampaignThirdVibe
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityThirdVibe
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderThirdVibe
        }
    }

    var laneName: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveLane
        case .campaignReview:
            AppStrings.Automation.exampleCampaignLane
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityLane
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderLane
        }
    }

    var schedule: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveSchedule
        case .campaignReview:
            AppStrings.Automation.exampleCampaignSchedule
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunitySchedule
        case .multiProviderReview:
            AppStrings.Automation.exampleMultiProviderSchedule
        }
    }

    /// Authored iteration bound when the scenario's first two Vibes form a loop
    /// group. nil = a strictly forward scenario.
    var loopIterations: Int? {
        switch self {
        case .multiProviderReview:
            3
        case .executiveBriefing, .campaignReview, .productOpportunity:
            nil
        }
    }

    /// The second Vibe reviews the first one's output, so it uses the review
    /// skill rather than the work skill.
    var secondVibeUsesReviewSkill: Bool {
        loopIterations != nil
    }
}
