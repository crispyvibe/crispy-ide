import Foundation

// MARK: - Centralized UI Strings
// All user-facing text is defined here using String(localized:) for localization support.
// Naming convention: {feature}.{context}.{element}
// To change any UI text, edit the corresponding value in Localizable.xcstrings — no code changes needed.

enum AppStrings {

    // MARK: - Common (shared action labels reused across multiple features)

    enum Common {
        static let done = String(localized: "common.done")
        static let cancel = String(localized: "common.cancel")
        static let close = String(localized: "common.close")
        static let save = String(localized: "common.save")
        static let delete = String(localized: "common.delete")
        static let rename = String(localized: "common.rename")
        static let retry = String(localized: "common.retry")
        static let ok = String(localized: "common.ok")
        static let back = String(localized: "common.back")
        static let next = String(localized: "common.next")
        static let skip = String(localized: "common.skip")
        static let reset = String(localized: "common.reset")
        static let add = String(localized: "common.add")
        static let all = String(localized: "common.all", defaultValue: "All")
        static let clear = String(localized: "common.clear")
        static let none = String(localized: "common.none")
        static let preview = String(localized: "common.preview")
        static let more = String(localized: "common.more")
        static let clearColor = String(localized: "common.clearColor")
    }

    // MARK: - App Update

    enum AppUpdate {
        static let upToDateTitle = String(localized: "appUpdate.upToDate.title")
        static let upToDateMessageFormat = String(localized: "appUpdate.upToDate.message")
        static let updateAvailableTitle = String(localized: "appUpdate.available.title")
        static let updateAvailableMessageFormat = String(localized: "appUpdate.available.message")
        static let downloadUpdate = String(localized: "appUpdate.available.download")
        static let later = String(localized: "appUpdate.available.later")
        static let releaseNotes = String(localized: "appUpdate.available.releaseNotes")
        static let checkFailedTitle = String(localized: "appUpdate.failed.title")

        static func upToDateMessage(version: String, build: String) -> String {
            String(
                format: upToDateMessageFormat,
                locale: Locale.current,
                version,
                build
            )
        }

        static func updateAvailableMessage(
            remoteVersion: String,
            remoteBuild: String,
            currentVersion: String,
            currentBuild: String
        ) -> String {
            String(
                format: updateAvailableMessageFormat,
                locale: Locale.current,
                remoteVersion,
                remoteBuild,
                currentVersion,
                currentBuild
            )
        }
    }

    // MARK: - Brand (non-localized constants)

    enum Brand {
        static let crispyvibes = "CRISPY"
    }

    // MARK: - Home

    enum Home {
        static let welcomeHero = String(localized: "home.welcome.hero")
        static let createVibeSpace = String(localized: "home.welcome.createVibeSpace")
        static let createNewVibeSpace = String(localized: "home.welcome.createNewVibeSpace")
        static let recentVibeSpaces = String(localized: "home.welcome.recentVibeSpaces")
        static let nothingRecentYet = String(localized: "home.welcome.nothingRecentYet")
        static let createOnceShowHere = String(localized: "home.welcome.createOnceShowHere")
        static let justYouAndYourVibe = String(localized: "home.welcome.justYouAndYourVibe")
        static let defaultVibeSpaceBaseName = String(localized: "home.welcome.defaultVibeSpaceBaseName")
        static let terminalVibeSpaceName = String(localized: "home.welcome.terminalVibeSpaceName")
        static let manageVibeSpacesButton = String(
            localized: "home.welcome.manageVibeSpacesButton",
            defaultValue: "Manage VibeSpaces"
        )
    }

    // MARK: - Onboarding

    enum Onboarding {
        static let disclaimerTitle = String(localized: "onboarding.disclaimer.title")
        static let telemetry = String(localized: "onboarding.disclaimer.telemetry")
        static let crashReporting = String(localized: "onboarding.disclaimer.crashReporting")
        static let asIs = String(localized: "onboarding.disclaimer.asIs")
        static let liability = String(localized: "onboarding.disclaimer.liability")
        static let justYouAndYourVibe = String(localized: "onboarding.disclaimer.justYouAndYourVibe")
        static let keychainNote = String(localized: "onboarding.disclaimer.keychainNote")
        static let acceptAndContinue = String(localized: "onboarding.disclaimer.acceptAndContinue")
        static let quit = String(localized: "onboarding.disclaimer.quit")
    }

    // MARK: - Shelf

    enum Shelf {
        static let title = String(localized: "shelf.title")
        static let emptyTitle = String(localized: "shelf.empty.title")
        static let emptyDescription = String(localized: "shelf.empty.description")
        static let filesOpenedFromFinder = String(localized: "shelf.filesOpenedFromFinder")
    }

    // MARK: - Todos (F053)

    enum Todos {
        static let title = String(localized: "todos.title")
        static let allInVibeSpace = String(localized: "todos.allInVibeSpace")
        static let scopeProject = String(localized: "todos.scope.project")
        static let scopeAll = String(localized: "todos.scope.all")
        static let quickAddPlaceholder = String(localized: "todos.quickAdd.placeholder")
        static let emptyTitle = String(localized: "todos.empty.title")
        static let emptyHint = String(localized: "todos.empty.hint")
        static let complete = String(localized: "todos.action.complete")
        static let reopen = String(localized: "todos.action.reopen", defaultValue: "Reopen")
        static let delete = String(localized: "todos.action.delete")
        static let titlePlaceholder = String(localized: "todos.title.placeholder")
        static let bodyPlaceholder = String(localized: "todos.body.placeholder")
        static let notesLabel = String(localized: "todos.notes.label")
        static let save = String(localized: "todos.action.save")
        static let cancel = String(localized: "todos.action.cancel")
        static let thread = String(localized: "todos.thread.title")
        static let threadEmpty = String(localized: "todos.thread.empty")
        static let messagePlaceholder = String(localized: "todos.message.placeholder")
        static let authorYou = String(localized: "todos.author.you")
        static let authorAgent = String(localized: "todos.author.agent")
        static let selectPrompt = String(localized: "todos.detail.selectPrompt")
        static let quickCapturePlaceholder = String(localized: "todos.quickCapture.placeholder")
        static let captureLandsIn = String(localized: "todos.capture.landsIn")
        static let captureNoProject = String(localized: "todos.capture.noProject")
        static let captureAdded = String(localized: "todos.capture.added")
        static let captureFailed = String(localized: "todos.capture.failed", defaultValue: "Couldn't add todo")
        static let searchPlaceholder = String(localized: "todos.search.placeholder", defaultValue: "Search todos")
        static let activeSection = String(localized: "todos.section.active", defaultValue: "Active")
        static let completedSection = String(localized: "todos.section.completed", defaultValue: "Completed")
        static let noMatches = String(localized: "todos.search.noMatches", defaultValue: "No matching todos")
        static let deleteConfirmTitle = String(localized: "todos.delete.confirm.title", defaultValue: "Delete this todo?")
        static let deleteConfirmMessage = String(
            localized: "todos.delete.confirm.message",
            defaultValue: "Its notes and thread are deleted with it. This can't be undone."
        )
        static let colorLabel = String(localized: "todos.color.label", defaultValue: "Color")
        static let colorNone = String(localized: "todos.color.none", defaultValue: "None")
        static let createdLabel = String(localized: "todos.meta.created", defaultValue: "Created")
        static let completedLabel = String(localized: "todos.meta.completed", defaultValue: "Completed")
        static let attachedFile = String(localized: "todos.meta.attachedFile", defaultValue: "Attached file")
        static let back = String(localized: "todos.action.back", defaultValue: "Back")
        static let editNotes = String(localized: "todos.action.editNotes", defaultValue: "Edit")
        static let dismissError = String(localized: "todos.error.dismiss", defaultValue: "Dismiss")
    }

    // MARK: - Vibe Lanes (F059)

    enum VibeLanes {
        static let title = String(localized: "vibeLanes.title", defaultValue: "Vibe Lanes")
        static let dashboard = String(localized: "vibeLanes.dashboard", defaultValue: "Dashboard")
        static let subtitle = String(
            localized: "vibeLanes.subtitle",
            defaultValue: "Agent work, tracked step by step."
        )
        static let manageLanes = String(localized: "vibeLanes.manageLanes", defaultValue: "Manage lanes")
        static let newTask = String(localized: "vibeLanes.newTask", defaultValue: "New task")
        static let startTask = String(localized: "vibeLanes.startTask", defaultValue: "Start task")
        static let startFirstTask = String(localized: "vibeLanes.startFirstTask", defaultValue: "Start first task")
        static let cancel = String(localized: "common.cancel")
        static let running = String(localized: "vibeLanes.state.running", defaultValue: "Running")
        static let needsYou = String(localized: "vibeLanes.state.needsYou", defaultValue: "Needs you")
        static let stopped = String(localized: "vibeLanes.state.stopped", defaultValue: "Stopped")
        static let completed = String(localized: "vibeLanes.state.completed", defaultValue: "Done")
        static let allTasks = String(localized: "vibeLanes.allTasks", defaultValue: "All tasks")
        static let noTasksTitle = String(localized: "vibeLanes.empty.title", defaultValue: "No task runs yet")
        static let noTasksBody = String(
            localized: "vibeLanes.empty.body",
            defaultValue: "Start with a small, well-bounded task."
        )
        static let describeTask = String(localized: "vibeLanes.new.describeTask", defaultValue: "Describe the work")
        static let taskPlaceholder = String(
            localized: "vibeLanes.new.taskPlaceholder",
            defaultValue: "Fix the failing payment tests"
        )
        static let chooseRoute = String(localized: "vibeLanes.new.chooseRoute", defaultValue: "Choose a route")
        static let suggested = String(localized: "vibeLanes.new.suggested", defaultValue: "Suggested")
        static let reviewRun = String(localized: "vibeLanes.new.reviewRun", defaultValue: "Review run")
        static let project = String(localized: "vibeLanes.project", defaultValue: "Project")
        static let route = String(localized: "vibeLanes.route", defaultValue: "Route")
        static let lane = String(localized: "vibeLanes.lane", defaultValue: "Lane")
        static let lanes = String(localized: "vibeLanes.lanes", defaultValue: "Lanes")
        static let yourLanes = String(localized: "vibeLanes.yourLanes", defaultValue: "Your lanes")
        static let newLane = String(localized: "vibeLanes.newLane", defaultValue: "New lane")
        static let editLane = String(localized: "vibeLanes.editLane", defaultValue: "Edit lane")
        static let task = String(localized: "vibeLanes.task", defaultValue: "Task")
        static let currentStep = String(localized: "vibeLanes.currentStep", defaultValue: "Current step")
        static let checkpoints = String(localized: "vibeLanes.checkpoints", defaultValue: "Checkpoints")
        static let stop = String(localized: "vibeLanes.stop", defaultValue: "Stop")
        static let keepGoing = String(localized: "vibeLanes.keepGoing", defaultValue: "Keep going")
        static let discard = String(localized: "vibeLanes.discard", defaultValue: "Discard")
        static let open = String(localized: "vibeLanes.open", defaultValue: "Open")
        static let answer = String(localized: "vibeLanes.answer", defaultValue: "Answer")
        static let deleteTask = String(localized: "vibeLanes.deleteTask", defaultValue: "Delete")
        static let taskNotFound = String(localized: "vibeLanes.taskNotFound", defaultValue: "Task not found")
        static let laneNotFound = String(localized: "vibeLanes.laneNotFound", defaultValue: "Lane not found")
        static let unavailable = String(localized: "vibeLanes.unavailable", defaultValue: "Vibe Lanes unavailable")
        static let noLaneDetail = String(localized: "vibeLanes.noLaneDetail", defaultValue: "Reusable task route")
        static let startFailed = String(
            localized: "vibeLanes.startFailed",
            defaultValue: "Could not start this task. Check that the lane still exists."
        )
        static let noProjectSelected = String(
            localized: "vibeLanes.noProjectSelected",
            defaultValue: "Open or focus a project to start a task. Vibe Lanes run inside a project, not your home folder."
        )
        static let reasonAttemptCap = String(localized: "vibeLanes.reason.attemptCap", defaultValue: "Attempt cap")
        static let reasonTimedOut = String(localized: "vibeLanes.reason.timedOut", defaultValue: "Timed out")
        static let reasonNoProgress = String(localized: "vibeLanes.reason.noProgress", defaultValue: "No progress")
        static let reasonFailedCheck = String(localized: "vibeLanes.reason.failedCheck", defaultValue: "Failed check")
        static let reasonStopped = String(localized: "vibeLanes.reason.stopped", defaultValue: "Stopped")
        static let reasonStoppedByYou = String(localized: "vibeLanes.reason.stoppedByYou", defaultValue: "Stopped by you")
        static let latestActivity = String(localized: "vibeLanes.latestActivity", defaultValue: "Latest activity")
        static let runLog = String(localized: "vibeLanes.runLog", defaultValue: "Run log")
        static let noRunLog = String(localized: "vibeLanes.noRunLog", defaultValue: "No run activity recorded yet.")
        static let agentNote = String(localized: "vibeLanes.agentNote", defaultValue: "Agent note")
        static let checkOutput = String(localized: "vibeLanes.checkOutput", defaultValue: "Check output")
        static let evidence = String(localized: "vibeLanes.evidence", defaultValue: "Evidence")
        static let verifierVerdict = String(localized: "vibeLanes.verifierVerdict", defaultValue: "Verifier verdict")
        static let verifierFeedback = String(localized: "vibeLanes.verifierFeedback", defaultValue: "Verifier feedback")
        static let openWorkerChat = String(localized: "vibeLanes.openWorkerChat", defaultValue: "Open worker chat")
        static let openVerifierChat = String(localized: "vibeLanes.openVerifierChat", defaultValue: "Open verifier chat")

        // MARK: Simplified model (Work Definition + Verification Definition)
        static let openReviewerChat = String(localized: "vibeLanes.openReviewerChat", defaultValue: "Open reviewer chat")
        static let verificationResult = String(localized: "vibeLanes.verificationResult", defaultValue: "Verification")
        static let verificationFeedback = String(localized: "vibeLanes.verificationFeedback", defaultValue: "Feedback")
        static let checkpointDoneWhen = String(localized: "vibeLanes.checkpoint.doneWhen", defaultValue: "Done when")
        static let checkpointGoal = String(localized: "vibeLanes.checkpoint.goal", defaultValue: "Goal")
        static let checkpointInstructions = String(localized: "vibeLanes.checkpoint.instructions", defaultValue: "Instructions")
        static let checkpointSkills = String(localized: "vibeLanes.checkpoint.skills", defaultValue: "Skills")
        static let checkpointNoSkills = String(localized: "vibeLanes.checkpoint.noSkills", defaultValue: "No skills declared")
        static let checkpointHandoff = String(localized: "vibeLanes.checkpoint.handoff", defaultValue: "Carry-forward")
        static let checkpointInputs = String(localized: "vibeLanes.checkpoint.inputs", defaultValue: "Inputs")
        static let checkpointProduces = String(localized: "vibeLanes.checkpoint.produces", defaultValue: "Produces")
        static let reasonMissingInput = String(localized: "vibeLanes.reason.missingInput", defaultValue: "Missing input")
        static let reasonMisAuthoredLane = String(localized: "vibeLanes.reason.misAuthoredLane", defaultValue: "Lane needs an unsupplied input")
        static let reasonSteerLimitReached = String(localized: "vibeLanes.reason.steerLimitReached", defaultValue: "Steer limit reached")
        static let supplyInput = String(localized: "vibeLanes.input.supply", defaultValue: "Supply input")
        static let steerTask = String(localized: "vibeLanes.input.steer", defaultValue: "Steer task")
        static let continueTask = String(localized: "vibeLanes.input.continue", defaultValue: "Continue")
        static let steeringGuidance = String(localized: "vibeLanes.input.steeringGuidance", defaultValue: "Steering guidance")
        static let lastFeedback = String(localized: "vibeLanes.input.lastFeedback", defaultValue: "Last feedback")
        static let requiredInput = String(localized: "vibeLanes.input.requiredInput", defaultValue: "Required input")
        static let exhaustedReason = String(localized: "vibeLanes.input.exhaustedReason", defaultValue: "Exhausted reason")
        static let remainingSteers = String(localized: "vibeLanes.input.remainingSteers", defaultValue: "Remaining steers")
        static let askUser = String(localized: "vibeLanes.editor.askUser", defaultValue: "Ask user")
        static let stopOnExhausted = String(localized: "vibeLanes.editor.stopOnExhausted", defaultValue: "Stop")
        static let escalateOnExhausted = String(localized: "vibeLanes.editor.escalateOnExhausted", defaultValue: "Ask to steer")
        static let laneNamePlaceholder = String(localized: "vibeLanes.editor.laneName.placeholder", defaultValue: "Lane name")
        static let laneDescriptionPlaceholder = String(localized: "vibeLanes.editor.laneDescription.placeholder", defaultValue: "Short description")
        static let deleteLane = String(localized: "vibeLanes.editor.deleteLane", defaultValue: "Delete")
        static let saved = String(localized: "vibeLanes.editor.saved", defaultValue: "Saved")
        static let saveLane = String(localized: "vibeLanes.editor.saveLane", defaultValue: "Save lane")
        static let editorCheckpoint = String(localized: "vibeLanes.editor.checkpoint", defaultValue: "Checkpoint")
        static let editorWork = String(localized: "vibeLanes.editor.work", defaultValue: "Work")
        static let editorStepKey = String(localized: "vibeLanes.editor.stepKey", defaultValue: "Step key")
        static let stepKeyPlaceholder = String(localized: "vibeLanes.editor.stepKey.placeholder", defaultValue: "step-key")
        static let editorGoal = String(localized: "vibeLanes.editor.goal", defaultValue: "Goal")
        static let goalPlaceholder = String(localized: "vibeLanes.editor.goal.placeholder", defaultValue: "What to accomplish at this step")
        static let editorSkillPaths = String(localized: "vibeLanes.editor.skillPaths", defaultValue: "Skill paths")
        static let addSkillPlaceholder = String(localized: "vibeLanes.editor.skillPaths.placeholder", defaultValue: "Add a skill folder path or SKILL.md file path")
        static let editorInstructions = String(localized: "vibeLanes.editor.instructions", defaultValue: "Instructions")
        static let instructionsPlaceholder = String(localized: "vibeLanes.editor.instructions.placeholder", defaultValue: "How to do it")
        static let editorVerification = String(localized: "vibeLanes.editor.verification", defaultValue: "Verification criteria")
        static let editorContract = String(localized: "vibeLanes.editor.contract", defaultValue: "Contract")
        static let editorBounds = String(localized: "vibeLanes.editor.bounds", defaultValue: "Bounds")
        static let maxAttempts = String(localized: "vibeLanes.editor.maxAttempts", defaultValue: "Max attempts")
        static let timeLimitMinutes = String(localized: "vibeLanes.editor.timeLimitMinutes", defaultValue: "Time limit (min)")
        static let whenExhausted = String(localized: "vibeLanes.editor.whenExhausted", defaultValue: "When exhausted")
        static let add = String(localized: "common.add", defaultValue: "Add")
        static let addInput = String(localized: "vibeLanes.editor.addInput", defaultValue: "Add input")
        static let addOutput = String(localized: "vibeLanes.editor.addOutput", defaultValue: "Add output")
        static let requiresInputs = String(localized: "vibeLanes.editor.requiresInputs", defaultValue: "Required inputs")
        static let producedOutputs = String(localized: "vibeLanes.editor.producedOutputs", defaultValue: "Produced outputs")
        static let noRequiredInputs = String(localized: "vibeLanes.editor.noRequiredInputs", defaultValue: "No required inputs")
        static let noProducedOutputs = String(localized: "vibeLanes.editor.noProducedOutputs", defaultValue: "No produced outputs")
        static let inputKeyPlaceholder = String(localized: "vibeLanes.editor.inputKey.placeholder", defaultValue: "input-key")
        static let inputPromptPlaceholder = String(localized: "vibeLanes.editor.inputPrompt.placeholder", defaultValue: "Prompt shown when this input is missing")
        static let outputKeyPlaceholder = String(localized: "vibeLanes.editor.outputKey.placeholder", defaultValue: "output-key")
        static let outputDetailPlaceholder = String(localized: "vibeLanes.editor.outputDetail.placeholder", defaultValue: "What this output should reference")
        static let moveCheckpointLeft = String(localized: "vibeLanes.editor.moveCheckpointLeft", defaultValue: "Move left")
        static let moveCheckpointRight = String(localized: "vibeLanes.editor.moveCheckpointRight", defaultValue: "Move right")
        static let keyNormalizationWarning = String(localized: "vibeLanes.editor.keyNormalizationWarning", defaultValue: "Checkpoint keys will be normalized to stable lowercase identifiers on save.")
        static let pass = String(localized: "vibeLanes.verdict.pass", defaultValue: "PASS")
        static let fail = String(localized: "vibeLanes.verdict.fail", defaultValue: "FAIL")
        static let lastVerificationResult = String(localized: "vibeLanes.lastVerificationResult", defaultValue: "Last verification result")
        static let carryForwardValues = String(localized: "vibeLanes.carryForwardValues", defaultValue: "Carry-forward values")
        static let reviewerFeedbackBeforeSteering = String(localized: "vibeLanes.input.reviewerFeedbackBeforeSteering", defaultValue: "Reviewer feedback before steering:")
        static let userSteeringGuidance = String(localized: "vibeLanes.input.userSteeringGuidance", defaultValue: "User steering guidance:")
        static let activityMissingInput = String(localized: "vibeLanes.activity.missingInput", defaultValue: "A required input was not available from earlier steps")
        static let activityMissingOutput = String(localized: "vibeLanes.activity.missingOutput", defaultValue: "The step did not report a declared output")
        static let checkpointNotStarted = String(localized: "vibeLanes.checkpoint.notStarted", defaultValue: "Not started")
        static let workerThread = String(localized: "vibeLanes.workerThread", defaultValue: "Worker thread")
        static let reviewerThread = String(localized: "vibeLanes.reviewerThread", defaultValue: "Reviewer thread")
        static let activity = String(localized: "vibeLanes.activity", defaultValue: "Activity")
        static let reasonVerificationFailed = String(localized: "vibeLanes.reason.verificationFailed", defaultValue: "Verification failed")
        static let reasonError = String(localized: "vibeLanes.reason.error", defaultValue: "Tool error")
        static let activityReviewerChatReady = String(localized: "vibeLanes.activity.reviewerChatReady", defaultValue: "Reviewer chat ready")
        static let activityReviewerReviewing = String(localized: "vibeLanes.activity.reviewerReviewing", defaultValue: "Reviewer reviewing the outcome")
        static let activityReviewerAccepted = String(localized: "vibeLanes.activity.reviewerAccepted", defaultValue: "Reviewer accepted the outcome")
        static let activityReviewerRejected = String(localized: "vibeLanes.activity.reviewerRejected", defaultValue: "Reviewer rejected the outcome; sending feedback to the worker")
        static let activityWritingHandoff = String(localized: "vibeLanes.activity.writingHandoff", defaultValue: "Writing handoff for the next step")
        static let activityWritingOutcome = String(localized: "vibeLanes.activity.writingOutcome", defaultValue: "Summarizing the final outcome")
        static let outcome = String(localized: "vibeLanes.outcome", defaultValue: "Outcome")
        static let stepHandoff = String(localized: "vibeLanes.stepHandoff", defaultValue: "Handoff")

        static func steerLimit(_ count: Int) -> String {
            String(
                format: String(localized: "vibeLanes.editor.steerLimit", defaultValue: "Steer limit: %d"),
                locale: Locale.current,
                count
            )
        }

        static func minutesShort(_ count: Int) -> String {
            String(
                format: String(localized: "vibeLanes.editor.minutesShort", defaultValue: "%dm"),
                locale: Locale.current,
                count
            )
        }

        static func steerRequestPrompt(checkpoint: String, reason: String) -> String {
            String(
                format: String(localized: "vibeLanes.input.steerPrompt", defaultValue: "Checkpoint %@ exhausted %@. Provide steering guidance or stop."),
                locale: Locale.current,
                checkpoint,
                reason
            )
        }

        static func supplyRequestPrompt(keys: String) -> String {
            String(
                format: String(localized: "vibeLanes.input.supplyPrompt", defaultValue: "Supply required input: %@"),
                locale: Locale.current,
                keys
            )
        }

        static let notificationNeedsYouTitle = String(
            localized: "vibeLanes.notification.needsYouTitle",
            defaultValue: "A task needs you"
        )

        static func stepCount(_ count: Int) -> String {
            String(
                format: String(localized: "vibeLanes.lane.stepCount", defaultValue: "%d steps"),
                locale: Locale.current,
                count
            )
        }

        static func stepOf(current: Int, total: Int) -> String {
            String(
                format: String(localized: "vibeLanes.task.stepOf", defaultValue: "Step %d of %d"),
                locale: Locale.current,
                current,
                total
            )
        }

        static let stepDefinition = String(
            localized: "vibeLanes.task.stepDefinition",
            defaultValue: "Step definition"
        )

        static let restoreStarterLanes = String(
            localized: "vibeLanes.lanes.restoreStarters",
            defaultValue: "Restore starters"
        )

        static let restoreStarterLanesHelp = String(
            localized: "vibeLanes.lanes.restoreStartersHelp",
            defaultValue: "Re-add deleted starter lanes and refresh unedited ones to the latest shipped versions. Lanes you have edited are never changed."
        )

        static let chooseProject = String(
            localized: "vibeLanes.newTask.chooseProject",
            defaultValue: "Choose…"
        )

        static let useFocusedProject = String(
            localized: "vibeLanes.newTask.useFocusedProject",
            defaultValue: "Use focused project"
        )

        static let noProjectShort = String(
            localized: "vibeLanes.newTask.noProjectShort",
            defaultValue: "No project selected"
        )

        static let agent = String(
            localized: "vibeLanes.newTask.agent",
            defaultValue: "Agent"
        )

        static func defaultAgent(_ name: String) -> String {
            String(
                format: String(localized: "vibeLanes.newTask.defaultAgent", defaultValue: "Default (%@)"),
                locale: Locale.current,
                name
            )
        }

        static let reviewStep = String(
            localized: "vibeLanes.review.title",
            defaultValue: "Verify this step"
        )

        static func reviewRequestPrompt(checkpoint: String) -> String {
            String(
                format: String(localized: "vibeLanes.review.prompt", defaultValue: "%@ finished its work. Verify the outcome yourself, then approve or request changes."),
                locale: Locale.current,
                checkpoint
            )
        }

        static let reviewHint = String(
            localized: "vibeLanes.review.hint",
            defaultValue: "Inspect the outcome yourself — project files, diff, or the worker thread — then decide."
        )

        static let reviewFeedbackPlaceholder = String(
            localized: "vibeLanes.review.feedbackPlaceholder",
            defaultValue: "What must change before this passes? (required to request changes)"
        )

        static let approve = String(
            localized: "vibeLanes.review.approve",
            defaultValue: "Approve"
        )

        static let requestChanges = String(
            localized: "vibeLanes.review.requestChanges",
            defaultValue: "Request changes"
        )

        static let approvedByYou = String(
            localized: "vibeLanes.review.approvedByYou",
            defaultValue: "Approved by you"
        )

        static let editorVerifiedBy = String(
            localized: "vibeLanes.editor.verifiedBy",
            defaultValue: "Verified by"
        )

        static let editorReviewerAgent = String(
            localized: "vibeLanes.editor.reviewerAgent",
            defaultValue: "Reviewer agent"
        )

        static let editorVerifiedByYou = String(
            localized: "vibeLanes.editor.verifiedByYou",
            defaultValue: "You"
        )

        static func notificationNeedsYouBody(task: String) -> String {
            String(
                format: String(localized: "vibeLanes.notification.needsYouBody", defaultValue: "“%@” is paused and waiting for your answer."),
                locale: Locale.current,
                task
            )
        }

        static func misAuthoredContractWarning(checkpoint: String, keys: String) -> String {
            String(
                format: String(localized: "vibeLanes.editor.misAuthoredContractWarning", defaultValue: "%@ requires unsupplied non-user input: %@"),
                locale: Locale.current,
                checkpoint,
                keys
            )
        }

        static func boundsSummary(attempts: Int, minutes: Int, behavior: String) -> String {
            String(
                format: String(localized: "vibeLanes.boundsSummary", defaultValue: "%d attempts, %d min, then %@"),
                locale: Locale.current,
                attempts,
                minutes,
                behavior
            )
        }

        static func activityWorking(checkpoint: String, current: Int, cap: Int) -> String {
            String(
                format: String(localized: "vibeLanes.activity.working", defaultValue: "Worker on %@, attempt %d of %d"),
                locale: Locale.current,
                checkpoint, current, cap
            )
        }

        static func activityRunningCommand(_ command: String) -> String {
            String(
                format: String(localized: "vibeLanes.activity.runningCommand", defaultValue: "Running check: %@"),
                locale: Locale.current,
                command.isEmpty ? String(localized: "vibeLanes.activity.check", defaultValue: "check") : command
            )
        }

        static func activityCommandPassed(exitCode: Int) -> String {
            String(
                format: String(localized: "vibeLanes.activity.commandPassed", defaultValue: "Check passed (exit %d)"),
                locale: Locale.current,
                exitCode
            )
        }

        static func activityCommandFailed(exitCode: Int) -> String {
            String(
                format: String(localized: "vibeLanes.activity.commandFailed", defaultValue: "Check failed (exit %d)"),
                locale: Locale.current,
                exitCode
            )
        }
        static let activityStarting = String(localized: "vibeLanes.activity.starting", defaultValue: "Starting task")
        static let activityDone = String(localized: "vibeLanes.activity.done", defaultValue: "Task completed")
        static let activityWorkerError = String(
            localized: "vibeLanes.activity.workerError",
            defaultValue: "The worker agent could not complete this step"
        )
        static let activityWorkerChatReady = String(
            localized: "vibeLanes.activity.workerChatReady",
            defaultValue: "Worker chat ready"
        )
        static let activityVerifierChatReady = String(
            localized: "vibeLanes.activity.verifierChatReady",
            defaultValue: "Verifier chat ready"
        )
        static let activityVerifierWorking = String(
            localized: "vibeLanes.activity.verifierWorking",
            defaultValue: "Verifier reviewing evidence"
        )
        static let activityVerifierAccepted = String(
            localized: "vibeLanes.activity.verifierAccepted",
            defaultValue: "Verifier accepted the checkpoint"
        )
        static let activityVerifierRejected = String(
            localized: "vibeLanes.activity.verifierRejected",
            defaultValue: "Verifier rejected the checkpoint; sending feedback to the worker"
        )

        static func activityCheckpointStarted(_ checkpoint: String) -> String {
            String(
                format: String(localized: "vibeLanes.activity.checkpointStarted", defaultValue: "Started checkpoint: %@"),
                locale: Locale.current,
                checkpoint
            )
        }

        static func activityAgentWorking(checkpoint: String, current: Int, cap: Int) -> String {
            String(
                format: String(localized: "vibeLanes.activity.agentWorking", defaultValue: "Agent working on %@, attempt %d of %d"),
                locale: Locale.current,
                checkpoint,
                current,
                cap
            )
        }

        static func activityRunningCheck(_ command: String) -> String {
            String(
                format: String(localized: "vibeLanes.activity.runningCheck", defaultValue: "Running check: %@"),
                locale: Locale.current,
                command.isEmpty ? String(localized: "vibeLanes.activity.check", defaultValue: "check") : command
            )
        }

        static func activityCheckPassed(exitCode: Int) -> String {
            String(
                format: String(localized: "vibeLanes.activity.checkPassed", defaultValue: "Check passed with exit %d"),
                locale: Locale.current,
                exitCode
            )
        }

        static func activityCheckFailed(exitCode: Int) -> String {
            String(
                format: String(localized: "vibeLanes.activity.checkFailed", defaultValue: "Check failed with exit %d"),
                locale: Locale.current,
                exitCode
            )
        }

        static func activityMovingTo(_ checkpoint: String) -> String {
            String(
                format: String(localized: "vibeLanes.activity.movingTo", defaultValue: "Moving to checkpoint: %@"),
                locale: Locale.current,
                checkpoint
            )
        }

        static func activityEscalatingStrategy(_ strategy: String) -> String {
            String(
                format: String(localized: "vibeLanes.activity.escalatingStrategy", defaultValue: "Stalled — escalating to strategy: %@"),
                locale: Locale.current,
                strategy
            )
        }

        static func activityStopped(_ reason: String) -> String {
            String(
                format: String(localized: "vibeLanes.activity.stopped", defaultValue: "Stopped: %@"),
                locale: Locale.current,
                reason
            )
        }

        static func attemptRunning(current: Int, cap: Int) -> String {
            String(
                format: String(localized: "vibeLanes.status.running", defaultValue: "Attempt %d of %d - Running"),
                locale: Locale.current,
                current,
                cap
            )
        }

        static func attempts(_ count: Int) -> String {
            String(
                format: count == 1
                    ? String(localized: "vibeLanes.attempts.singular", defaultValue: "%d attempt")
                    : String(localized: "vibeLanes.attempts.plural", defaultValue: "%d attempts"),
                locale: Locale.current,
                count
            )
        }

        static func attemptLabel(_ index: Int) -> String {
            String(
                format: String(localized: "vibeLanes.checkpoint.attemptN", defaultValue: "Attempt %d"),
                locale: Locale.current,
                index
            )
        }

        static func doneAttempts(_ count: Int) -> String {
            String(
                format: count == 1
                    ? String(localized: "vibeLanes.status.doneAttempts.singular", defaultValue: "Done - %d attempt")
                    : String(localized: "vibeLanes.status.doneAttempts.plural", defaultValue: "Done - %d attempts"),
                locale: Locale.current,
                count
            )
        }

        static func stopped(_ reason: String) -> String {
            String(
                format: String(localized: "vibeLanes.status.stopped", defaultValue: "%@ - Stopped"),
                locale: Locale.current,
                reason
            )
        }

        static func dashboardSubtitle(lane: String, project: String) -> String {
            String(
                format: String(localized: "vibeLanes.dashboard.subtitle", defaultValue: "%@ - %@"),
                locale: Locale.current,
                lane,
                project
            )
        }

        static func askUserInput(_ key: String) -> String {
            String(
                format: String(localized: "vibeLanes.checkpoint.askUserInput", defaultValue: "%@ (ask user)"),
                locale: Locale.current,
                key
            )
        }

        static func outputDescription(_ detail: String) -> String {
            String(
                format: String(localized: "vibeLanes.checkpoint.outputDescription", defaultValue: "Description: %@"),
                locale: Locale.current,
                detail
            )
        }
    }

    // MARK: - VibeSpace Creation

    enum VibeSpaceCreation {
        static let nameYourVibeSpace = String(localized: "vibeSpaceCreation.nameYourVibeSpace")
        static let vibeSpaceName = String(localized: "vibeSpaceCreation.vibeSpaceName")
        static let choosePreset = String(localized: "vibeSpaceCreation.choosePreset")
        static let noDefaultSelected = String(localized: "vibeSpaceCreation.noDefaultSelected")
        static let folderNameOverride = String(localized: "vibeSpaceCreation.folderNameOverride")
        static let label = String(localized: "vibeSpaceCreation.label")
    }

    // MARK: - VibeSpace

    enum VibeSpace {
        static let noProjects = String(localized: "vibespace.noProjects")
        static let addProjectToStart = String(localized: "vibespace.addProjectToStart")
        static let closeVibeSpace = String(localized: "vibespace.closeVibeSpace")

        // F021-R12 / R13: Parked project UI strings.
        static let parkedProjectsHeader = String(localized: "vibespace.parkedProjects.header", defaultValue: "Parked Projects")
        static let parkProjectAction = String(localized: "vibespace.parkProject.action", defaultValue: "Park Project")
        static let activateProjectAction = String(localized: "vibespace.activateProject.action", defaultValue: "Activate Project")
        // F021-R18 / R19: remove a project (active or parked) via context menu.
        static let removeProjectAction = String(localized: "vibespace.removeProject.action", defaultValue: "Remove Project")
    }

    // MARK: - Worktree (F055 / F056: unified sidebar + git worktrees)

    enum Worktree {
        static let newFile = String(localized: "worktree.newFile", defaultValue: "New File")
        static let newFolder = String(localized: "worktree.newFolder", defaultValue: "New Folder")
        static let refresh = String(localized: "worktree.refresh", defaultValue: "Refresh")
        static let newAgentChat = String(localized: "worktree.newAgentChat", defaultValue: "New Agent Chat")
        static let newFileOrFolderHelp = String(localized: "worktree.newFileOrFolder.help", defaultValue: "New File or Folder")
        static let noChanges = String(localized: "worktree.noChanges", defaultValue: "No changes")
        static let noConversations = String(localized: "worktree.noConversations", defaultValue: "No conversations")
        static let notAGitRepository = String(localized: "worktree.notAGitRepository", defaultValue: "Not a Git repository")
        static let untitledThread = String(localized: "worktree.untitledThread", defaultValue: "Untitled")
        static let closeWorktree = String(localized: "worktree.close", defaultValue: "Close Worktree")
        static let deleteWorktree = String(localized: "worktree.delete", defaultValue: "Delete Worktree…")
        static let openAsProject = String(localized: "worktree.openAsProject", defaultValue: "Open as Project")
        static let open = String(localized: "worktree.open", defaultValue: "Open")
        static let newWorktree = String(localized: "worktree.new", defaultValue: "New Worktree…")
        static let openAsProjectHelp = String(localized: "worktree.openAsProject.help", defaultValue: "Open as Project")

        static func otherWorktrees(_ count: Int) -> String {
            String(localized: "worktree.otherWorktrees", defaultValue: "Other worktrees (\(count))")
        }
        static func worktreeCount(_ count: Int) -> String {
            String(localized: "worktree.count", defaultValue: "\(count) worktrees")
        }
        /// Repo count split into opened vs not-yet-opened worktrees so the
        /// number matches what's visible ("1 open · 2 other"). Falls back to the
        /// plain count when there are no other worktrees.
        static func worktreeCountSplit(open: Int, other: Int) -> String {
            other == 0
                ? worktreeCount(open)
                : String(localized: "worktree.count.split", defaultValue: "\(open) open · \(other) other")
        }

        // MARK: Accessibility labels / values
        static let showFiles = String(localized: "worktree.a11y.showFiles", defaultValue: "Show files")
        static func showChanges(_ count: Int) -> String {
            String(localized: "worktree.a11y.showChanges", defaultValue: "Show changes, \(count) changed")
        }
        static func showConversations(_ count: Int) -> String {
            String(localized: "worktree.a11y.showConversations", defaultValue: "Show conversations, \(count)")
        }
        static func changedFilesValue(_ count: Int) -> String {
            String(localized: "worktree.a11y.changedFiles", defaultValue: "\(count) changed files")
        }
        static func openWorktreeLabel(_ name: String) -> String {
            String(localized: "worktree.a11y.openWorktree", defaultValue: "Open worktree \(name)")
        }
        static func collapseExpandLabel(_ title: String) -> String {
            String(localized: "worktree.a11y.collapseExpand", defaultValue: "\(title), collapsible section")
        }
        static let expandedHint = String(localized: "worktree.a11y.expanded", defaultValue: "Expanded")
        static let collapsedHint = String(localized: "worktree.a11y.collapsed", defaultValue: "Collapsed")

        // Delete confirmation
        static func deleteConfirmTitle(_ name: String) -> String {
            String(localized: "worktree.delete.title", defaultValue: "Delete worktree “\(name)”?")
        }
        static let deleteConfirmMessage = String(localized: "worktree.delete.message", defaultValue: "This removes the worktree’s directory from disk and unregisters it from git. This can’t be undone.")
        static let deleteButton = String(localized: "worktree.delete.button", defaultValue: "Delete")
        static let forceDeleteTitle = String(localized: "worktree.forceDelete.title", defaultValue: "Couldn’t delete worktree")
        static func forceDeleteMessage(_ error: String) -> String {
            String(localized: "worktree.forceDelete.message", defaultValue: "\(error)\n\nForce delete? Any uncommitted changes in the worktree will be lost.")
        }
        static let forceDeleteButton = String(localized: "worktree.forceDelete.button", defaultValue: "Force Delete")

        // New-worktree prompt
        static let newTitle = String(localized: "worktree.newPrompt.title", defaultValue: "New Worktree")
        static let newMessage = String(localized: "worktree.newPrompt.message", defaultValue: "Create a new git worktree on a new branch.")
        static let newCreateButton = String(localized: "worktree.newPrompt.create", defaultValue: "Create")
        static let newBranchPlaceholder = String(localized: "worktree.newPrompt.placeholder", defaultValue: "new-branch-name")
        static let createFailedTitle = String(localized: "worktree.createFailed.title", defaultValue: "Couldn’t create worktree")

        static let cancel = String(localized: "common.cancel")
    }

    // MARK: - Sidebar

    enum Sidebar {
        static let filesTab = String(localized: "sidebar.tab.files")
        static let navigationTab = String(localized: "sidebar.tab.navigation")
        static let sessionsTab = String(localized: "sidebar.tab.sessions", defaultValue: "Sessions")
        static let conversationsTab = String(localized: "sidebar.tab.conversations", defaultValue: "Conversations")

        enum Sessions {
            static let title = String(localized: "sidebar.sessions.title", defaultValue: "Live tmux sessions")
            static let currentVibeSpace = String(localized: "sidebar.sessions.currentVibeSpace", defaultValue: "Current VibeSpace")
            static let otherVibeSpaces = String(localized: "sidebar.sessions.otherVibeSpaces", defaultValue: "Other VibeSpaces")
            static let emptyTitle = String(localized: "sidebar.sessions.empty.title", defaultValue: "No tmux sessions")
            static let emptyDescription = String(localized: "sidebar.sessions.empty.description", defaultValue: "Open a local or remote terminal with tmux to browse sessions here.")
            static let refresh = String(localized: "sidebar.sessions.refresh", defaultValue: "Refresh sessions")
            static let preview = String(localized: "sidebar.sessions.preview", defaultValue: "Preview session")
            static let openInProject = String(localized: "sidebar.sessions.openInProject", defaultValue: "Open in project")
            static let copyAttachCommand = String(localized: "sidebar.sessions.copyAttachCommand", defaultValue: "Copy attach command")
            static let terminate = String(localized: "sidebar.sessions.terminate", defaultValue: "Terminate session")
            static let otherLocalTitle = String(localized: "sidebar.sessions.otherLocal.title", defaultValue: "Other Local Sessions")
            static let projectTerminal = String(localized: "sidebar.sessions.projectTerminal", defaultValue: "Project Terminal")
            static let localTmuxUnavailable = String(localized: "sidebar.sessions.local.tmuxUnavailable", defaultValue: "tmux is not available on this Mac.")
            static let localEnableTmux = String(localized: "sidebar.sessions.local.enableTmux", defaultValue: "Enable tmux integration to attach local sessions here.")
            static let localNoSessions = String(localized: "sidebar.sessions.local.none", defaultValue: "No local tmux sessions found for this project.")
            static let remoteReconnect = String(localized: "sidebar.sessions.remote.reconnect", defaultValue: "Reconnect this host to browse its tmux sessions.")
            static let remoteTmuxUnavailable = String(localized: "sidebar.sessions.remote.tmuxUnavailable", defaultValue: "tmux is not available on this host.")
            static let remoteNoSessions = String(localized: "sidebar.sessions.remote.none", defaultValue: "No remote tmux sessions found for this project.")

            static func otherRemoteTitle(_ hostName: String) -> String {
                String(
                    format: String(localized: "sidebar.sessions.otherRemote.title", defaultValue: "%@ Other Sessions"),
                    locale: Locale.current,
                    hostName
                )
            }

            static func remoteConnecting(_ hostName: String) -> String {
                String(
                    format: String(localized: "sidebar.sessions.remote.connecting", defaultValue: "Connecting to %@…"),
                    locale: Locale.current,
                    hostName
                )
            }
        }

        enum Conversations {
            static let crispyvibes = String(localized: "sidebar.conversations.crispyvibes", defaultValue: "Crispy")
            static let external = String(localized: "sidebar.conversations.external", defaultValue: "External")
        }

        enum ExternalSessions {
            static let searchPlaceholder = String(localized: "sidebar.externalSessions.search", defaultValue: "Search external sessions...")
            static let refresh = String(localized: "sidebar.externalSessions.refresh", defaultValue: "Refresh external sessions")
            static let loading = String(localized: "sidebar.externalSessions.loading", defaultValue: "Loading external sessions")
            static let loadFailed = String(localized: "sidebar.externalSessions.loadFailed", defaultValue: "External sessions unavailable")
            static let emptyTitle = String(localized: "sidebar.externalSessions.empty.title", defaultValue: "No external sessions")
            static let emptyDescription = String(localized: "sidebar.externalSessions.empty.description", defaultValue: "Codex, Claude Code, and Kiro CLI sessions found on this Mac will appear here.")
            static let parseDiagnostics = String(localized: "sidebar.externalSessions.parseDiagnostics", defaultValue: "Parse diagnostics")
            static let preview = String(localized: "sidebar.externalSessions.preview", defaultValue: "Preview")
            static let copyResumeCommand = String(localized: "sidebar.externalSessions.copyResumeCommand", defaultValue: "Copy Resume Command")
            static let copySourcePath = String(localized: "sidebar.externalSessions.copySourcePath", defaultValue: "Copy Source Path")
            static let thisWeek = String(localized: "sidebar.externalSessions.thisWeek", defaultValue: "This Week")
            static let lastWeek = String(localized: "sidebar.externalSessions.lastWeek", defaultValue: "Last Week")
            static let earlier = String(localized: "sidebar.externalSessions.earlier", defaultValue: "Earlier")
            static let sourcePath = String(localized: "sidebar.externalSessions.sourcePath", defaultValue: "Source Path")
            static let sessionId = String(localized: "sidebar.externalSessions.sessionId", defaultValue: "Session ID")

            static func matchCount(_ count: Int) -> String {
                String(
                    format: String(localized: "sidebar.externalSessions.matchCount", defaultValue: "%d matches"),
                    locale: Locale.current,
                    count
                )
            }
        }
    }

    // MARK: - Explorer

    enum Explorer {
        static let searchFiles = String(localized: "explorer.searchFiles")
        static let noFolderSelected = String(localized: "explorer.noFolderSelected")
        static let chooseFolderToBrowse = String(localized: "explorer.chooseFolderToBrowse")
        static let openVibeSpaceToBrowse = String(localized: "explorer.openVibeSpaceToBrowse")
        static let noFilesLoaded = String(localized: "explorer.noFilesLoaded")
        static let loadingFiles = String(localized: "explorer.loadingFiles")
        static let newFile = String(localized: "explorer.newFile")
        static let newFolder = String(localized: "explorer.newFolder")
        static let openInTerminal = String(localized: "explorer.openInTerminal")
        static let openInSplitHorizontal = String(localized: "explorer.openInSplitHorizontal")
        static let openInSplitVertical = String(localized: "explorer.openInSplitVertical")
        static let revealInFinder = String(localized: "explorer.revealInFinder")
        static let deleteItemTitle = String(localized: "explorer.deleteItem.title")
        static let deleteItemConfirm = String(localized: "explorer.deleteItem.confirm")
        static let errorTitle = String(localized: "explorer.error.title")
        static let refreshFileList = String(localized: "explorer.refreshFileList")
        static let createNewFile = String(localized: "explorer.createNewFile")
        static let createNewFolder = String(localized: "explorer.createNewFolder")
    }

    // MARK: - Whiteboard

    /// F052: Excalidraw whiteboards.
    enum Whiteboard {
        static let title = String(localized: "whiteboard.title", defaultValue: "Whiteboard")
        static let new = String(localized: "whiteboard.new", defaultValue: "New Whiteboard")
        static let canvasAccessibilityLabel = String(
            localized: "whiteboard.canvas.accessibilityLabel",
            defaultValue: "Whiteboard canvas"
        )
    }

    /// LaTeX documents (KaTeX-rendered preview).
    enum LaTeX {
        static let previewAccessibilityLabel = String(
            localized: "latex.preview.accessibilityLabel",
            defaultValue: "LaTeX preview"
        )
        static let paletteMatrix = String(
            localized: "latex.palette.matrix",
            defaultValue: "matrix"
        )
        static let runtimeUnavailable = String(
            localized: "latex.runtime.unavailable",
            defaultValue: "The LaTeX preview runtime is unavailable. Rebuild the app to restore it."
        )
        static let compiling = String(
            localized: "latex.compiled.compiling",
            defaultValue: "Compiling…"
        )
        static let compileFailedTitle = String(
            localized: "latex.compiled.failed",
            defaultValue: "Compilation failed"
        )
        static let toolchainMissingTitle = String(
            localized: "latex.compiled.toolchain.title",
            defaultValue: "Full LaTeX preview needs a TeX engine"
        )
        static let toolchainMissingBody = String(
            localized: "latex.compiled.toolchain.body",
            defaultValue: "Install BasicTeX (~100 MB) or MacTeX to render the real PDF. The Edit and Source tabs work without it."
        )
        static let toolchainRecheck = String(
            localized: "latex.compiled.toolchain.recheck",
            defaultValue: "Recheck"
        )
        static let toolchainUseEdit = String(
            localized: "latex.compiled.toolchain.useEdit",
            defaultValue: "Use Edit Tab"
        )
        static let toolchainGetBasicTeX = String(
            localized: "latex.compiled.toolchain.getBasicTeX",
            defaultValue: "Get BasicTeX"
        )
    }

    // MARK: - Source Control

    enum SourceControl {
        static let title = String(localized: "sourceControl.title")
        static let loading = String(localized: "sourceControl.loading")
        static let gitUnavailable = String(localized: "sourceControl.gitUnavailable")
        static let gitUnavailableDescription = String(localized: "sourceControl.gitUnavailable.description")
        static let unavailable = String(localized: "sourceControl.unavailable")
        static let noReposFound = String(localized: "sourceControl.noReposFound")
        static let noReposDescription = String(localized: "sourceControl.noReposDescription")
        static let cloneRepository = String(localized: "sourceControl.cloneRepository")
        static let loadingRepoStatus = String(localized: "sourceControl.loadingRepoStatus")
        static let noChanges = String(localized: "sourceControl.noChanges")
        static let commitMessage = String(localized: "sourceControl.commitMessage")
        static let commit = String(localized: "sourceControl.commit")
        static let push = String(localized: "sourceControl.push")
        static let pull = String(localized: "sourceControl.pull")
        static let fetch = String(localized: "sourceControl.fetch")
        static let stageAll = String(localized: "sourceControl.stageAll")
        static let undoAll = String(localized: "sourceControl.undoAll")
        static let undoAllTitle = String(localized: "sourceControl.undoAll.title")
        static let undoAllMessage = String(localized: "sourceControl.undoAll.message")
        static let discardChanges = String(localized: "sourceControl.discardChanges")
        static let noCommitsMatched = String(localized: "sourceControl.noCommitsMatched")
        static let loadingHistory = String(localized: "sourceControl.loadingHistory")
        static let openVibeSpaceToInspect = String(localized: "sourceControl.openVibeSpaceToInspect")
        static let refreshRepository = String(localized: "sourceControl.refreshRepository")
        static let refreshGitStatus = String(localized: "sourceControl.refreshGitStatus")
        static let stage = String(localized: "sourceControl.stage")
        static let unstage = String(localized: "sourceControl.unstage")
        static let undoChanges = String(localized: "sourceControl.undoChanges")
        static let viewCommitHistory = String(localized: "sourceControl.viewCommitHistory")
        static let viewFileHistory = String(localized: "sourceControl.viewFileHistory")
        static let noDiffContent = String(localized: "sourceControl.noDiffContent")
    }

    // MARK: - Clone Repository

    enum CloneRepository {
        static let title = String(localized: "cloneRepository.title")
        static let repositoryURL = String(localized: "cloneRepository.repositoryURL")
        static let destinationFolder = String(localized: "cloneRepository.destinationFolder")
        static let choose = String(localized: "cloneRepository.choose")
        static let clone = String(localized: "cloneRepository.clone")
        static let pasteURLInstead = String(localized: "cloneRepository.pasteURLInstead")
        static let refreshGitHubAccess = String(localized: "cloneRepository.refreshGitHubAccess")
        static let searchGitHub = String(localized: "cloneRepository.searchGitHub")
        static let noGitHubRepos = String(localized: "cloneRepository.noGitHubRepos")
        static let gitHubDescription = String(localized: "cloneRepository.gitHubDescription")
        static let checkingGitHub = String(localized: "cloneRepository.checkingGitHub")
        static let pickRepoOrPasteURL = String(localized: "cloneRepository.pickRepoOrPasteURL")
        static let optionalDefaultsFromRepo = String(localized: "cloneRepository.optionalDefaultsFromRepo")
        static let gitHubSignInNote = String(localized: "cloneRepository.gitHubSignInNote")
        static let `private` = String(localized: "cloneRepository.private")
    }

    // MARK: - Terminal

    enum Terminal {
        // General
        static let newTerminal = String(localized: "terminal.newTerminal")
        static let splitTerminal = String(localized: "terminal.splitTerminal")
        static let newTemporaryTerminal = String(localized: "terminal.newTemporaryTerminal")
        static let createTerminal = String(localized: "terminal.createTerminal")
        static let closeTerminal = String(localized: "terminal.closeTerminal")
        static let noSession = String(localized: "terminal.noSession")
        static let noSessionDescription = String(localized: "terminal.noSession.description")
        static let sessionInactive = String(localized: "terminal.sessionInactive")
        static let temporary = String(localized: "terminal.temporary")
        static let selectedUnavailable = String(localized: "terminal.selectedUnavailable")
        static let noToolsOnPath = String(localized: "terminal.noToolsOnPath")

        // Board tile actions
        enum Tile {
            static let minimize = String(localized: "terminal.tile.minimize")
            static let close = String(localized: "terminal.tile.close")
            static let remove = String(localized: "terminal.tile.remove")
            static let restore = String(localized: "terminal.tile.restore")
            static let closeMinimized = String(localized: "terminal.tile.closeMinimized")
            static let sendToNewBoardWindow = String(localized: "terminal.tile.sendToNewBoardWindow")
            static let sendToBoardWindow = String(localized: "terminal.tile.sendToBoardWindow")
            static let sendAllFromProjectToNewBoardWindow = String(localized: "terminal.tile.sendAllFromProjectToNewBoardWindow")
            static let primaryBoardWindow = String(localized: "terminal.tile.primaryBoardWindow")
            static let boardWindow = String(localized: "terminal.tile.boardWindow")
            static let panes = String(localized: "terminal.tile.panes")
        }

        enum Window {
            static let renameWindow = String(
                localized: "terminal.window.renameWindow",
                defaultValue: "Rename Window"
            )
            static let renameWindowPrompt = String(
                localized: "terminal.window.renameWindow.prompt",
                defaultValue: "Enter a display name for this window."
            )
        }

        enum ContextSummary {
            static let copySummary = String(
                localized: "terminal.contextSummary.copySummary",
                defaultValue: "Copy summary"
            )
            /// Placeholder text shown in the timeline / headline when the user submitted
            /// input that was suppressed from the terminal display (e.g., a password
            /// prompt with echo disabled). The literal text never enters the LLM prompt
            /// or the summary history. F041-R17.
            static let sensitiveInformationPlaceholder = String(
                localized: "terminal.contextSummary.sensitiveInformation",
                defaultValue: "sensitive information"
            )
        }

        // Board
        static let boardTitle = String(localized: "terminal.board.title")

        enum ComposeTriggers {
            static let pickerTitle = String(
                localized: "terminal.composeTriggers.picker.title",
                defaultValue: "Insert"
            )
            static let typeToSearch = String(
                localized: "terminal.composeTriggers.query.placeholder",
                defaultValue: "Type to search..."
            )
            static let noResults = String(
                localized: "terminal.composeTriggers.empty",
                defaultValue: "Results will appear here."
            )
            static let promptFailed = String(
                localized: "terminal.composeTriggers.prompts.failed",
                defaultValue: "Prompt action failed. Check Text Services settings."
            )
            static let searchingPaths = String(
                localized: "terminal.composeTriggers.paths.searching",
                defaultValue: "Searching files..."
            )
            static let generateCommand = String(
                localized: "terminal.composeTriggers.prompts.generate",
                defaultValue: "Generate Command"
            )
            static let generateCommandDescription = String(
                localized: "terminal.composeTriggers.prompts.generate.description",
                defaultValue: "Turn a plain-language request into one shell command."
            )
            static let shortcutKind = String(
                localized: "terminal.composeTriggers.kind.shortcut",
                defaultValue: "Shortcut"
            )
            static let fileKind = String(
                localized: "terminal.composeTriggers.kind.file",
                defaultValue: "File"
            )
            static let directoryKind = String(
                localized: "terminal.composeTriggers.kind.directory",
                defaultValue: "Directory"
            )
            static let promptActionKind = String(
                localized: "terminal.composeTriggers.kind.promptAction",
                defaultValue: "Prompt Action"
            )
            static let promptActionsSection = String(
                localized: "terminal.composeTriggers.section.prompts",
                defaultValue: "Prompt Actions"
            )
            static let shortcutsSection = String(
                localized: "terminal.composeTriggers.section.shortcuts",
                defaultValue: "Shortcuts"
            )
            static let pathsSection = String(
                localized: "terminal.composeTriggers.section.paths",
                defaultValue: "Files and Folders"
            )
            static let actionsSection = String(
                localized: "terminal.composeTriggers.section.actions",
                defaultValue: "Actions"
            )
            static let rightArrowGenerateHint = String(
                localized: "terminal.composeTriggers.hint.generate",
                defaultValue: "Right Arrow selects Generate"
            )
            static let confirmHint = String(
                localized: "terminal.composeTriggers.hint.confirm",
                defaultValue: "Tab/Enter confirm"
            )
            static let pathResultSingular = String(
                localized: "terminal.composeTriggers.results.paths.singular",
                defaultValue: "%d path result"
            )
            static let pathResultPlural = String(
                localized: "terminal.composeTriggers.results.paths.plural",
                defaultValue: "%d path results"
            )
            static let shortcutResultSingular = String(
                localized: "terminal.composeTriggers.results.shortcuts.singular",
                defaultValue: "%d shortcut"
            )
            static let shortcutResultPlural = String(
                localized: "terminal.composeTriggers.results.shortcuts.plural",
                defaultValue: "%d shortcuts"
            )

            static func triggerDetail(_ trigger: String) -> String {
                String(
                    format: String(
                        localized: "terminal.composeTriggers.detail",
                        defaultValue: "Type %@ at the start of a token to search files, shortcuts, or prompt actions. Up/Down selects, Tab or Enter confirms."
                    ),
                    locale: Locale.current,
                    trigger
                )
            }

            static func pathResultCount(_ count: Int) -> String {
                String(
                    format: count == 1 ? pathResultSingular : pathResultPlural,
                    locale: Locale.current,
                    count
                )
            }

            static func shortcutResultCount(_ count: Int) -> String {
                String(
                    format: count == 1 ? shortcutResultSingular : shortcutResultPlural,
                    locale: Locale.current,
                    count
                )
            }
        }
    }

    // MARK: - Terminal Shortcuts

    enum TerminalShortcuts {
        static let manageShortcuts = String(localized: "terminalShortcuts.manage")
        static let noShortcuts = String(localized: "terminalShortcuts.noShortcuts")
        static let createQuickCommands = String(localized: "terminalShortcuts.createQuickCommands")
        static let shortcutName = String(localized: "terminalShortcuts.shortcutName")
        static let command = String(localized: "terminalShortcuts.command")
        static let workingDirectory = String(localized: "terminalShortcuts.workingDirectory")
        static let currentTerminal = String(localized: "terminalShortcuts.currentTerminal")
        static let newTerminal = String(localized: "terminalShortcuts.newTerminal")
        static let temporaryTerminal = String(localized: "terminalShortcuts.temporaryTerminal")
        static let scopedShortcuts = String(localized: "terminalShortcuts.scopedShortcuts")
    }

    // MARK: - VibeCast

    enum VibeCast {
        static let title = String(localized: "vibeCast.title")
        static let noTerminal = String(localized: "vibeCast.noTerminal")
        static let noTerminalDescription = String(localized: "vibeCast.noTerminal.description")
    }

    // MARK: - Comments (F049)

    enum Comments {
        static let panelTitle = String(localized: "comments.panel.title", defaultValue: "Comments")
        static let closePanel = String(localized: "comments.panel.close", defaultValue: "Close comments panel")
        static let searchPlaceholder = String(localized: "comments.search.placeholder", defaultValue: "Search comments")
        static let filterActive = String(localized: "comments.filter.active", defaultValue: "Active")
        static let filterResolved = String(localized: "comments.filter.resolved", defaultValue: "Resolved")
        static let filterStale = String(localized: "comments.filter.stale", defaultValue: "Stale")
        static let filterAll = String(localized: "comments.filter.all", defaultValue: "All")
        static let emptyStateTitle = String(localized: "comments.empty.title", defaultValue: "No comments")
        static let emptyStateBody = String(localized: "comments.empty.body", defaultValue: "Click the + button to add a comment, or post one from the CLI.")
        static let composerPlaceholder = String(localized: "comments.composer.placeholder", defaultValue: "Write a comment…")
        static let replyPlaceholder = String(localized: "comments.reply.placeholder", defaultValue: "Write a reply…")
        static let replyAction = String(localized: "comments.reply.action", defaultValue: "Reply")
        static let reply = String(localized: "comments.reply.submit", defaultValue: "Reply")
        static let submit = String(localized: "comments.submit", defaultValue: "Submit")
        static let resolve = String(localized: "comments.resolve", defaultValue: "Resolve")
        static let reopen = String(localized: "comments.reopen", defaultValue: "Reopen")
        static let editedBadge = String(localized: "comments.edited.badge", defaultValue: "edited")
        static let staleLabel = String(localized: "comments.stale.label", defaultValue: "Stale — anchor lost")
        static let staleOriginalAnchor = String(localized: "comments.stale.originalAnchor", defaultValue: "Originally anchored to:")
        static let userAnonymous = String(localized: "comments.author.user", defaultValue: "You")
        static let agentAnonymous = String(localized: "comments.author.agent", defaultValue: "Agent")
        static let gutterActiveTooltip = String(localized: "comments.gutter.activeTooltip", defaultValue: "Active comment")
        static let gutterResolvedTooltip = String(localized: "comments.gutter.resolvedTooltip", defaultValue: "Resolved comment")
        static let gutterStaleTooltip = String(localized: "comments.gutter.staleTooltip", defaultValue: "Stale comment — anchor lost")
        static let crossFileTitle = String(localized: "comments.crossFile.title", defaultValue: "All Comments in Vibespace")
        static let crossFileEmptyTitle = String(localized: "comments.crossFile.empty.title", defaultValue: "No comments yet")
        static let crossFileEmptyBody = String(localized: "comments.crossFile.empty.body", defaultValue: "Add comments from the file viewer or via the CLI.")
        static let crossFileSectionFiles = String(localized: "comments.crossFile.section.files", defaultValue: "Files")
        static let crossFileSectionBrowsers = String(localized: "comments.crossFile.section.browsers", defaultValue: "Browsers")
        static let toolbarToggleHelp = String(localized: "comments.toolbar.toggle.help", defaultValue: "Toggle comments panel")
        static let toolbarAddHelp = String(localized: "comments.toolbar.add.help", defaultValue: "Add a comment")

        /// Format string: "%lld replies"
        static let repliesCount = String(localized: "comments.replies.count", defaultValue: "%lld replies")

        static func composerHeading(forLine line: Int) -> String {
            let format = String(localized: "comments.composer.heading", defaultValue: "New comment at line %lld")
            return String(format: format, locale: Locale.current, line)
        }

        /// Localized "L%lld" line label used in the cross-file thread row.
        static func lineLabel(_ line: Int) -> String {
            let format = String(localized: "comments.lineLabel", defaultValue: "L%lld")
            return String(format: format, locale: Locale.current, line)
        }

        /// Localized "+%lld" overflow indicator for the gutter strip.
        static func gutterOverflow(_ count: Int) -> String {
            let format = String(localized: "comments.gutter.overflow", defaultValue: "+%lld")
            return String(format: format, locale: Locale.current, count)
        }

        /// Localized "%lld" or "%lld / %lld" panel header count label.
        static func threadCountLabel(active: Int, total: Int) -> String {
            if active == total {
                let format = String(localized: "comments.panel.countSingle", defaultValue: "%lld")
                return String(format: format, locale: Locale.current, total)
            }
            let format = String(localized: "comments.panel.countSplit", defaultValue: "%lld / %lld")
            return String(format: format, locale: Locale.current, active, total)
        }

        /// Localized file-row label "lastComponent — fullPath".
        static func crossFileFileLabel(name: String, path: String) -> String {
            let format = String(localized: "comments.crossFile.fileLabel", defaultValue: "%@ — %@")
            return String(format: format, locale: Locale.current, name, path)
        }
    }

    // MARK: - Content Viewer

    enum ContentViewer {
        static let noContent = String(localized: "contentViewer.noContent")
        static let noContentDescription = String(localized: "contentViewer.noContent.description")
        static let emptyPane = String(localized: "contentViewer.emptyPane")
        static let emptyPaneDescription = String(localized: "contentViewer.emptyPane.description")
        static let splitHorizontal = String(localized: "contentViewer.splitHorizontal")
        static let splitVertical = String(localized: "contentViewer.splitVertical")
        static let toggleOrientation = String(localized: "contentViewer.toggleOrientation")
        static let closePane = String(localized: "contentViewer.closePane")
        static let scopeFocusedProject = String(localized: "contentViewer.scope.focusedProject")
        static let scopeAllProjects = String(localized: "contentViewer.scope.allProjects")
        static let terminalUnavailable = String(localized: "contentViewer.terminalUnavailable")
        static let terminalUnavailableDescription = String(localized: "contentViewer.terminalUnavailable.description")
    }

    // MARK: - Editor

    enum Editor {
        static let find = String(localized: "editor.find")
        static let replace = String(localized: "editor.replace")
        static let replaceNext = String(localized: "editor.replaceNext")
        static let replaceAll = String(localized: "editor.replaceAll")
        static let bold = String(localized: "editor.bold")
        static let italic = String(localized: "editor.italic")
        static let link = String(localized: "editor.link")
        static let image = String(localized: "editor.image")
        static let codeBlock = String(localized: "editor.codeBlock")
        static let quote = String(localized: "editor.quote")
        static let bulletList = String(localized: "editor.bulletList")
        static let numberedList = String(localized: "editor.numberedList")
        static let h1 = String(localized: "editor.h1")
        static let h2 = String(localized: "editor.h2")
        static let rule = String(localized: "editor.rule")
        static let table = String(localized: "editor.table")
        static let annotate = String(localized: "editor.annotate")
        static let annotationText = String(localized: "editor.annotationText")
        static let crop = String(localized: "editor.crop")
        static let applyCrop = String(localized: "editor.applyCrop")
        static let draw = String(localized: "editor.draw")
        static let unsaved = String(localized: "editor.unsaved")
        static let cannotPreview = String(localized: "editor.cannotPreview")
        static let viewModeRich = String(localized: "editor.viewMode.rich", defaultValue: "Rich")
        static let viewModeEdit = String(localized: "editor.viewMode.edit", defaultValue: "Edit")
        static let viewModeSource = String(localized: "editor.viewMode.source", defaultValue: "Source")
        static let viewModeCompiled = String(localized: "editor.viewMode.compiled", defaultValue: "PDF")
        static let viewModePreview = String(localized: "editor.viewMode.preview", defaultValue: "Preview")
    }

    // MARK: - Settings

    enum Settings {
        // General
        static let appTitle = String(localized: "settings.app.title")
        static let appSubtitle = String(localized: "settings.app.subtitle")

        // Theme
        enum Theme {
            static let useSystem = String(localized: "settings.theme.useSystem")
            static let customize = String(localized: "settings.theme.customize")
            static let resetCustom = String(localized: "settings.theme.resetCustom")
            static let useMidnightBase = String(localized: "settings.theme.useMidnightBase")
        }

        static let themeOverrideWarning = String(localized: "settings.theme.overrideWarning")
        static let typographyPreview = String(localized: "settings.typography.preview")
        static let customTokenHint = String(localized: "settings.theme.customTokenHint")

        // Container Style
        enum ContainerStyle {
            static let title = String(localized: "settings.containerStyle.title")
            static let description = String(localized: "settings.containerStyle.description")
            static let borderShapeTitle = String(localized: "settings.containerStyle.borderShape.title")
            static let borderShapeDetail = String(localized: "settings.containerStyle.borderShape.detail")
            static let showBordersTitle = String(localized: "settings.containerStyle.showBorders.title")
            static let showBordersDetail = String(localized: "settings.containerStyle.showBorders.detail")
        }

        // Account
        enum Account {
            static let signOut = String(localized: "settings.account.signOut")
        }

        // Updates
        enum Updates {
            static let checkNow = String(localized: "settings.updates.checkNow")
            static let resetFeedURL = String(localized: "settings.updates.resetFeedURL")
        }

        // Services
        enum Services {
            static let resetDefaults = String(localized: "settings.services.resetDefaults")
            static let rephrasePrompt = String(localized: "settings.services.rephrasePrompt")
            static let researchPrompt = String(localized: "settings.services.researchPrompt")
            static let defaultAgent = String(localized: "settings.services.defaultAgent")
        }

        enum Terminal {
            static let inlineTriggerTitle = String(
                localized: "settings.terminal.inlineTrigger.title",
                defaultValue: "Inline insert trigger"
            )
            static let inlineTriggerDetail = String(
                localized: "settings.terminal.inlineTrigger.detail",
                defaultValue: "Used at the start of spotlight compose input to open the insert picker."
            )
        }

        // Reset
        enum Reset {
            static let title = String(localized: "settings.reset.title")
            static let message = String(localized: "settings.reset.message")
            static let localState = String(localized: "settings.reset.localState")
        }

        static let cannotBeUndone = String(localized: "settings.reset.cannotBeUndone")

        // VibeSpaces panel
        enum VibeSpaces {
            static let cardTitle = String(
                localized: "settings.vibespaces.card.title",
                defaultValue: "Your VibeSpaces"
            )
            static let cardDescription = String(
                localized: "settings.vibespaces.card.description",
                defaultValue: "Open vibespaces from your full library or remove ones you no longer need. Double-click a row to open it."
            )
            static let searchPlaceholder = String(
                localized: "settings.vibespaces.searchPlaceholder",
                defaultValue: "Search vibespaces"
            )
            static let columnName = String(
                localized: "settings.vibespaces.column.name",
                defaultValue: "Name"
            )
            static let columnProjectFolders = String(
                localized: "settings.vibespaces.column.projectFolders",
                defaultValue: "Project Folders"
            )
            static let columnActions = String(
                localized: "settings.vibespaces.column.actions",
                defaultValue: "Actions"
            )
            static let openRowTooltip = String(
                localized: "settings.vibespaces.openRowTooltip",
                defaultValue: "Open vibespace"
            )
            static let deleteRowTooltip = String(
                localized: "settings.vibespaces.deleteRowTooltip",
                defaultValue: "Delete vibespace"
            )
            static let emptyTitle = String(
                localized: "settings.vibespaces.empty.title",
                defaultValue: "No vibespaces yet"
            )
            static let emptySubtitle = String(
                localized: "settings.vibespaces.empty.subtitle",
                defaultValue: "Create a vibespace from the welcome screen and it will show up here."
            )
            static let emptySearchTitle = String(
                localized: "settings.vibespaces.emptySearch.title",
                defaultValue: "No matches"
            )
            static let openSelected = String(
                localized: "settings.vibespaces.openSelected",
                defaultValue: "Open"
            )
            static let deleteSelected = String(
                localized: "settings.vibespaces.deleteSelected",
                defaultValue: "Delete"
            )
            static let deleteAlertTitle = String(
                localized: "settings.vibespaces.deleteAlert.title",
                defaultValue: "Delete VibeSpaces?"
            )
            static let deleteAlertConfirm = String(
                localized: "settings.vibespaces.deleteAlert.confirm",
                defaultValue: "Delete"
            )
            static let deleteAlertCancel = String(
                localized: "settings.vibespaces.deleteAlert.cancel",
                defaultValue: "Cancel"
            )
            static let loadingFooter = String(
                localized: "settings.vibespaces.loadingFooter",
                defaultValue: "Loading vibespaces…"
            )

            static func countFooter(_ count: Int) -> String {
                let template = String(
                    localized: "settings.vibespaces.countFooter",
                    defaultValue: "%lld vibespaces"
                )
                return String(format: template, locale: .current, count)
            }

            static func selectionFooter(_ selected: Int, _ total: Int) -> String {
                let template = String(
                    localized: "settings.vibespaces.selectionFooter",
                    defaultValue: "%1$lld of %2$lld selected"
                )
                return String(format: template, locale: .current, selected, total)
            }

            static func deleteAlertMessage(_ count: Int) -> String {
                if count == 1 {
                    return String(
                        localized: "settings.vibespaces.deleteAlert.messageSingle",
                        defaultValue: "This vibespace and its persisted state will be permanently deleted. This cannot be undone."
                    )
                }
                let template = String(
                    localized: "settings.vibespaces.deleteAlert.messageMany",
                    defaultValue: "%lld vibespaces and their persisted state will be permanently deleted. This cannot be undone."
                )
                return String(format: template, locale: .current, count)
            }
        }

        // Experimental
        enum Experimental {
            static let title = String(localized: "settings.experimental.title")
            static let subtitle = String(localized: "settings.experimental.subtitle")
            static let cardTitle = String(localized: "settings.experimental.card.title")
            static let cardDescription = String(localized: "settings.experimental.card.description")
            static let acpDefaultsCardTitle = String(
                localized: "settings.experimental.acpDefaults.card.title",
                defaultValue: "ACP Agent Defaults"
            )
            static let acpDefaultsCardDescription = String(
                localized: "settings.experimental.acpDefaults.card.description",
                defaultValue: "Pick the structured ACP agent Crispy should use by default for focused-project conversations."
            )
            static let acpDefaultAgentTitle = String(
                localized: "settings.experimental.acpDefaults.defaultAgent.title",
                defaultValue: "Default ACP agent"
            )
            static let acpDefaultAgentEmpty = String(
                localized: "settings.experimental.acpDefaults.defaultAgent.empty",
                defaultValue: "No ACP agent selected"
            )
            static let acpCustomAgentsTitle = String(
                localized: "settings.experimental.acpDefaults.customAgents.title",
                defaultValue: "Custom ACP agents"
            )
            static let acpCustomAgentName = String(
                localized: "settings.experimental.acpDefaults.customAgents.name",
                defaultValue: "Name"
            )
            static let acpCustomAgentExecutable = String(
                localized: "settings.experimental.acpDefaults.customAgents.executable",
                defaultValue: "Executable"
            )
            static let acpCustomAgentArguments = String(
                localized: "settings.experimental.acpDefaults.customAgents.arguments",
                defaultValue: "Arguments"
            )
            static let tmuxIntegrationTitle = String(localized: "settings.experimental.tmux.title")
            static let tmuxIntegrationDescription = String(localized: "settings.experimental.tmux.description")
            static let acpObservabilityTitle = String(
                localized: "settings.experimental.acpObservability.title",
                defaultValue: "ACP Diagnostics"
            )
            static let acpObservabilityDescription = String(
                localized: "settings.experimental.acpObservability.description",
                defaultValue: "Show ACP diagnostics in Developer Tools while using ACP conversations. This does not enable or disable ACP itself."
            )
            static let acpObservabilityVerboseTitle = String(
                localized: "settings.experimental.acpObservabilityVerbose.title",
                defaultValue: "Verbose ACP diagnostics"
            )
            static let acpObservabilityVerboseDescription = String(
                localized: "settings.experimental.acpObservabilityVerbose.description",
                defaultValue: "Capture additional low-level ACP events for debugging."
            )
            static let tmuxSessionBehaviorTitle = String(localized: "settings.experimental.tmux.sessionBehavior.title")
            static let tmuxTabCloseBehaviorTitle = String(localized: "settings.experimental.tmux.tabCloseBehavior.title")
            static let tmuxBehaviorDetach = String(localized: "settings.experimental.tmux.sessionBehavior.detach")
            static let tmuxBehaviorTerminate = String(localized: "settings.experimental.tmux.sessionBehavior.terminate")
            static let tmuxManagerTitle = String(localized: "settings.experimental.tmux.manager.title")
            static let tmuxManagerEmpty = String(localized: "settings.experimental.tmux.manager.empty")
            static let tmuxManagerActive = String(localized: "settings.experimental.tmux.manager.active")
            static let tmuxManagerOrphaned = String(localized: "settings.experimental.tmux.manager.orphaned")
            static let tmuxManagerKill = String(localized: "settings.experimental.tmux.manager.kill")
            static let tmuxManagerKillAllOrphans = String(localized: "settings.experimental.tmux.manager.killAllOrphans")
            static let tmuxManagerSessionCount = String(localized: "settings.experimental.tmux.manager.sessionCount")
        }

        enum ACPAgent {
            static let cardTitle = String(
                localized: "settings.acpAgent.card.title",
                defaultValue: "Agent Defaults"
            )
            static let cardDescription = String(
                localized: "settings.acpAgent.card.description",
                defaultValue: "Choose the default structured agent and manage custom ACP-compatible commands."
            )
            static let defaultAgentTitle = String(
                localized: "settings.acpAgent.defaultAgent.title",
                defaultValue: "Default agent"
            )
            static let defaultAgentEmpty = String(
                localized: "settings.acpAgent.defaultAgent.empty",
                defaultValue: "No agent selected"
            )
            static let trustModeTitle = String(
                localized: "settings.acpAgent.trustMode.title",
                defaultValue: "Trust mode"
            )
            static let modelTitle = String(
                localized: "settings.acpAgent.model.title",
                defaultValue: "Model"
            )
            static let reasoningTitle = String(
                localized: "settings.acpAgent.reasoning.title",
                defaultValue: "Reasoning"
            )
            static let customAgentsTitle = String(
                localized: "settings.acpAgent.customAgents.title",
                defaultValue: "Custom ACP agents"
            )
            static let customAgentName = String(
                localized: "settings.acpAgent.customAgents.name",
                defaultValue: "Name"
            )
            static let customAgentExecutable = String(
                localized: "settings.acpAgent.customAgents.executable",
                defaultValue: "Executable"
            )
            static let customAgentArguments = String(
                localized: "settings.acpAgent.customAgents.arguments",
                defaultValue: "Arguments"
            )
        }

        // Nerd
        enum Nerd {
            static let title = String(localized: "settings.nerd.title")
            static let subtitle = String(localized: "settings.nerd.subtitle")
            static let cardTitle = String(localized: "settings.nerd.card.title")
            static let cardDescription = String(localized: "settings.nerd.card.description")
            static let terminalEngineTitle = String(localized: "settings.nerd.terminalEngine.title")
            static let terminalEngineDescription = String(localized: "settings.nerd.terminalEngine.description")
        }

    }

    enum ACP {
        static let setupTrustMode = String(
            localized: "acp.setup.trustMode",
            defaultValue: "Trust Mode"
        )
        static let setupModel = String(
            localized: "acp.setup.model",
            defaultValue: "Model"
        )
        static let setupReasoning = String(
            localized: "acp.setup.reasoning",
            defaultValue: "Reasoning"
        )
        static let agentContentTitle = String(
            localized: "acp.agentContent.title",
            defaultValue: "Agent"
        )
        static let openAgent = String(
            localized: "acp.agentContent.open",
            defaultValue: "Open Agent"
        )
        static let closeAgentTile = String(
            localized: "acp.agentContent.closeTile",
            defaultValue: "Close Agent Tile"
        )
        static let unavailableTitle = String(
            localized: "acp.unavailable.title",
            defaultValue: "Agent Unavailable"
        )
        static let unavailableDescription = String(
            localized: "acp.unavailable.description",
            defaultValue: "This ACP pane could not be restored."
        )
        static let managedSessionWaiting = String(
            localized: "acp.managedSession.waiting",
            defaultValue: "Waiting for lane session"
        )
        static let managedSessionPendingTitle = String(
            localized: "acp.managedSession.pending.title",
            defaultValue: "Waiting for lane session"
        )
        static let managedSessionPendingDescription = String(
            localized: "acp.managedSession.pending.description",
            defaultValue: "The worker or verifier chat will appear here as soon as the lane agent starts."
        )
        static let connectedEmptyTimelineTitle = String(
            localized: "acp.connectedEmptyTimeline.title",
            defaultValue: "Connected"
        )
        static let connectedEmptyTimelineDescription = String(
            localized: "acp.connectedEmptyTimeline.description",
            defaultValue: "Waiting for the first agent update."
        )
    }

    // MARK: - VibeSpace Settings

    enum VibeSpaceSettings {
        static let title = String(localized: "vibespaceSettings.title")
        static let chooseProject = String(localized: "vibespaceSettings.chooseProject")
        static let dragToReorder = String(localized: "vibespaceSettings.dragToReorder")
        static let perProjectOverrides = String(localized: "vibespaceSettings.perProjectOverrides")
        static let noProjectVibeSpace = String(localized: "vibespaceSettings.noProjectVibeSpace")
        static let trustLevel = String(localized: "vibespaceSettings.trustLevel")
        static let usesDefaults = String(localized: "vibespaceSettings.usesDefaults")
        static let scanLimitsHint = String(localized: "vibespaceSettings.scanLimitsHint")
        static let settingsUnavailable = String(localized: "vibespaceSettings.unavailable")
        static let shortcutCommandsTitle = String(localized: "vibespaceSettings.shortcuts.title")
        static let shortcutCommandsSubtitle = String(localized: "vibespaceSettings.shortcuts.subtitle")
        static let shortcutCommandsCardTitle = String(localized: "vibespaceSettings.shortcuts.cardTitle")
        static let shortcutCommandsCardDescription = String(localized: "vibespaceSettings.shortcuts.cardDescription")
        static let vibespaceShortcutSection = String(localized: "vibespaceSettings.shortcuts.vibespaceSection")
        static let projectShortcutSectionPrefix = String(localized: "vibespaceSettings.shortcuts.projectSectionPrefix")
        static let shortcutScopeVibeSpace = String(localized: "vibespaceSettings.shortcuts.scope.vibespace")
        static let shortcutScopeProject = String(localized: "vibespaceSettings.shortcuts.scope.project")
        static let shortcutColumnName = String(localized: "vibespaceSettings.shortcuts.column.name")
        static let shortcutColumnCommand = String(localized: "vibespaceSettings.shortcuts.column.command")
        static let shortcutColumnOpenIn = String(localized: "vibespaceSettings.shortcuts.column.openIn")
        static let shortcutColumnTarget = String(localized: "vibespaceSettings.shortcuts.column.target")
        static let shortcutColumnScope = String(localized: "vibespaceSettings.shortcuts.column.scope")
        static let shortcutColumnProject = String(localized: "vibespaceSettings.shortcuts.column.project")
        static let addShortcut = String(localized: "vibespaceSettings.shortcuts.add")
        static let selectProject = String(localized: "vibespaceSettings.shortcuts.selectProject")
        static let shortcutProjectsDescription = String(localized: "vibespaceSettings.shortcuts.projectsDescription")
    }

    // MARK: - Walkthrough

    enum Walkthrough {
        static let keyboardShortcuts = String(localized: "walkthrough.keyboardShortcuts")
    }

    // MARK: - Toolbar

    enum Toolbar {
        static let switchToDetailed = String(localized: "toolbar.switchToDetailed")
        static let switchToTerminalBoard = String(localized: "toolbar.switchToTerminalBoard")
        static let addProject = String(localized: "toolbar.addProject")
        static let projectColor = String(localized: "toolbar.projectColor")
        static let closeProject = String(localized: "toolbar.closeProject")
    }

    // MARK: - Alerts

    enum Alert {
        static let vibespaceConfigModified = String(localized: "alert.vibespaceConfigModified")
        static let vibespaceConfigModifiedMessage = String(localized: "alert.vibespaceConfigModified.message")
        static let iUnderstand = String(localized: "alert.iUnderstand")

        static func vibespaceConfigModifiedMessage(vibespaceName: String) -> String {
            String(
                format: vibespaceConfigModifiedMessage,
                locale: Locale.current,
                vibespaceName
            )
        }
    }

    // MARK: - Link Preview

    enum LinkPreview {
        static let openInBrowser = String(localized: "linkPreview.openInBrowser")
    }

    enum Browser {
        static let addressBarPlaceholder = String(localized: "browser.addressBarPlaceholder", defaultValue: "URL or search")
        static let back = String(localized: "browser.back", defaultValue: "Browser Back")
        static let forward = String(localized: "browser.forward", defaultValue: "Browser Forward")
        static let addressField = String(localized: "browser.addressField", defaultValue: "Browser Address")
        static let zoomOut = String(localized: "browser.zoomOut", defaultValue: "Zoom Out")
        static let zoomIn = String(localized: "browser.zoomIn", defaultValue: "Zoom In")
        static let zoomLevel = String(localized: "browser.zoomLevel", defaultValue: "Browser Zoom")
        static let resetZoom = String(localized: "browser.resetZoom", defaultValue: "Reset Zoom")
        static let stopLoading = String(localized: "browser.stopLoading", defaultValue: "Stop Loading")
        static let reload = String(localized: "browser.reload", defaultValue: "Reload")
        static let findInPage = String(localized: "browser.findInPage", defaultValue: "Find in Page")
        static let findPlaceholder = String(localized: "browser.findPlaceholder", defaultValue: "Find…")
        static let newTab = String(localized: "browser.newTab", defaultValue: "New Tab")
        static let failedToLoad = String(localized: "browser.failedToLoad", defaultValue: "Failed to load")
        static let insecureConnectionTitle = String(localized: "browser.insecureConnectionTitle", defaultValue: "Connection isn\u{2019}t secure")
        static let openInDefaultBrowser = String(localized: "browser.openInDefaultBrowser", defaultValue: "Open in Default Browser")
        static let proceed = String(localized: "browser.proceed", defaultValue: "Proceed")
        static let dialogFallbackTitle = String(localized: "browser.dialogFallbackTitle", defaultValue: "This page says:")
        static let downloadFailed = String(localized: "browser.downloadFailed", defaultValue: "Download Failed")
        static let openInNewTab = String(localized: "browser.openInNewTab", defaultValue: "Open Link in New Tab")
        static let downloading = String(localized: "browser.downloading", defaultValue: "Downloading…")
    }
}
