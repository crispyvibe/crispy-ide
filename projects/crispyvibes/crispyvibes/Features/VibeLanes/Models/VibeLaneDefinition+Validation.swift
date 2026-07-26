import Foundation

/// Structural problems that make a lane unsafe or impossible to execute.
/// UI wording belongs in `AppStrings`; this type is shared by UI, CLI, loops,
/// and task creation so every entry point enforces the same contract.
enum VibeLaneDefinitionIssue: Equatable, Sendable {
    case missingLaneName
    case missingCheckpoints
    case invalidSteerLimit
    case emptyCheckpointKey(index: Int)
    case duplicateCheckpointKey(index: Int)
    case missingGoal(index: Int)
    case missingVerification(index: Int)
    case invalidBounds(index: Int)
    case emptyInputKey(index: Int)
    case duplicateInputKey(index: Int, key: String)
    case emptyOutputKey(index: Int)
    case duplicateOutputKey(index: Int, key: String)
    case unsatisfiedInput(index: Int, key: String)
    /// The checkpoint pins a `(vibeID, version)` that is no longer in the store,
    /// so its work/verification content could not be hydrated. Marked explicitly
    /// rather than inferred from the resulting empty goal, so an unresolved
    /// reference can never be mistaken for a merely incomplete draft.
    case unresolvedVibeReference(index: Int, vibeID: UUID, version: Int)

    var checkpointIndex: Int? {
        switch self {
        case .emptyCheckpointKey(let index),
             .duplicateCheckpointKey(let index),
             .missingGoal(let index),
             .missingVerification(let index),
             .invalidBounds(let index),
             .emptyInputKey(let index),
             .duplicateInputKey(let index, _),
             .emptyOutputKey(let index),
             .duplicateOutputKey(let index, _),
             .unsatisfiedInput(let index, _),
             .unresolvedVibeReference(let index, _, _):
            return index
        case .missingLaneName, .missingCheckpoints, .invalidSteerLimit:
            return nil
        }
    }

    /// Empty and duplicate checkpoint keys are repaired by the normal save path.
    var isRepairedOnEditorSave: Bool {
        switch self {
        case .emptyCheckpointKey, .duplicateCheckpointKey:
            return true
        default:
            return false
        }
    }
}

extension VibeLaneCheckpoint {
    var hasCompleteExpectationDefinition: Bool {
        !work.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !verify.isEmpty
            && bounds.maxAttempts > 0
            && bounds.timeoutSeconds > 0
    }
}

extension VibeLaneDefinition {
    var validationIssues: [VibeLaneDefinitionIssue] {
        var issues: [VibeLaneDefinitionIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingLaneName)
        }
        if checkpoints.isEmpty {
            issues.append(.missingCheckpoints)
        }
        if steerLimit < 0 {
            issues.append(.invalidSteerLimit)
        }

        var checkpointKeys = Set<String>()
        var producedKeys = Set<String>()
        let orderedIndices = checkpoints.indices.sorted {
            let leftOrder = checkpoints[$0].order
            let rightOrder = checkpoints[$1].order
            return leftOrder == rightOrder ? $0 < $1 : leftOrder < rightOrder
        }
        for index in orderedIndices {
            let checkpoint = checkpoints[index]
            let checkpointKey = checkpoint.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if checkpointKey.isEmpty {
                issues.append(.emptyCheckpointKey(index: index))
            } else if !checkpointKeys.insert(checkpointKey).inserted {
                issues.append(.duplicateCheckpointKey(index: index))
            }
            if checkpoint.unresolvedVibeReference {
                issues.append(.unresolvedVibeReference(
                    index: index,
                    vibeID: checkpoint.vibeID ?? UUID(),
                    version: checkpoint.vibeVersion ?? 0
                ))
            }
            if checkpoint.work.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.missingGoal(index: index))
            }
            if checkpoint.verify.isEmpty {
                issues.append(.missingVerification(index: index))
            }
            if checkpoint.bounds.maxAttempts <= 0 || checkpoint.bounds.timeoutSeconds <= 0 {
                issues.append(.invalidBounds(index: index))
            }

            var inputKeys = Set<String>()
            for input in checkpoint.inputRequirements {
                let key = input.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty {
                    issues.append(.emptyInputKey(index: index))
                } else if !inputKeys.insert(key).inserted {
                    issues.append(.duplicateInputKey(index: index, key: key))
                } else if !input.askUser && !producedKeys.contains(key) {
                    issues.append(.unsatisfiedInput(index: index, key: key))
                }
            }

            var outputKeys = Set<String>()
            for output in checkpoint.outputDeclarations {
                let key = output.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if key.isEmpty {
                    issues.append(.emptyOutputKey(index: index))
                } else if !outputKeys.insert(key).inserted {
                    issues.append(.duplicateOutputKey(index: index, key: key))
                } else {
                    producedKeys.insert(key)
                }
            }
        }
        return issues
    }

    var isRunnable: Bool {
        validationIssues.isEmpty
    }
}
