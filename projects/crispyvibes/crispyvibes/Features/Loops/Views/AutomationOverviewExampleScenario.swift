import Foundation

enum AutomationOverviewExampleScenario: String, CaseIterable, Identifiable {
    case executiveBriefing
    case campaignReview
    case productOpportunity

    var id: Self { self }

    var title: String {
        switch self {
        case .executiveBriefing:
            AppStrings.Automation.exampleExecutiveTitle
        case .campaignReview:
            AppStrings.Automation.exampleCampaignTitle
        case .productOpportunity:
            AppStrings.Automation.exampleOpportunityTitle
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
        }
    }
}
