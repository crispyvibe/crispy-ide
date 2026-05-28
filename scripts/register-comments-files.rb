#!/usr/bin/env ruby
# F049: register the new Comments feature Swift files in the Xcode project.
#
# Strategy: walk to the existing top-level "crispyvibes" group (the source
# folder), then create child groups using ONLY the segment name. Xcode
# resolves paths via `sourceTree = "<group>"` so each segment composes
# correctly with its parent.
require 'xcodeproj'

PROJECT_PATH = File.expand_path(
  '../projects/crispyvibes/crispyvibes.xcodeproj',
  __dir__
)
project = Xcodeproj::Project.open(PROJECT_PATH)

main_target = project.targets.find { |t| t.name == 'crispyvibes' }
abort('main target not found') unless main_target

# Find the top-level "crispyvibes" source group (the one mapped to
# projects/crispyvibes/crispyvibes/). It is a direct child of main_group.
top_group = project.main_group.groups.find { |g|
  g.path == 'crispyvibes' || g.display_name == 'crispyvibes'
}
abort('crispyvibes top group not found') unless top_group

# Walk into a sub-group, creating with `path = segment` (relative to parent).
def child(group, name, create_path: true)
  existing = group.groups.find { |g| g.display_name == name || g.path == name }
  return existing if existing
  if create_path
    group.new_group(name, name)
  else
    g = group.new_group(name)
    g.set_source_tree('<group>')
    g
  end
end

def add_swift(group, target, abs_path)
  rel = File.basename(abs_path)
  existing = group.files.find { |f| f.path == rel }
  if existing
    puts "  (already registered) #{rel}"
    return existing
  end
  ref = group.new_reference(rel)
  ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(ref, true)
  puts "  added #{rel}"
  ref
end

# Resolve into Features → Editor → Comments → {Models,ViewModels,Services,Views}
features = child(top_group, 'Features')
editor   = child(features, 'Editor')
comments = child(editor, 'Comments')
agent_cli = child(features, 'AgentCLI')

models     = child(comments, 'Models')
view_models = child(comments, 'ViewModels')
services   = child(comments, 'Services')
views      = child(comments, 'Views')

base = File.expand_path('../projects/crispyvibes/crispyvibes', __dir__)

entries = [
  [models, "#{base}/Features/Editor/Comments/Models/CommentModels.swift"],
  [view_models, "#{base}/Features/Editor/Comments/ViewModels/VibeSpaceCommentStore.swift"],
  [view_models, "#{base}/Features/Editor/Comments/ViewModels/VibeSpaceCommentStore+Helpers.swift"],
  [view_models, "#{base}/Features/Editor/Comments/ViewModels/CommentsPanelStore.swift"],
  [view_models, "#{base}/Features/Editor/Comments/ViewModels/CrossFileCommentsViewModel.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/CommentAnchorRelocator.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/CodeEditorCommentBridge.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/CodeEditorCommentBridgeEnvironment.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/CommentLifecycleCoordinator.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/CommentSurfaceBridge.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/BrowserCommentURLNormalizer.swift"],
  [services, "#{base}/Features/Editor/Comments/Services/BrowserSurfaceBridge.swift"],
  [comments, "#{base}/Features/Editor/Comments/CommentsNotifications.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CommentsPanelView.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CommentThreadView.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CommentComposerView.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CommentGutterIndicator.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CrossFileCommentsView.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CommentsFloatingButton.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/CommentsCodeEditorOverlay.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/FileContentWithCommentsPanel.swift"],
  [views, "#{base}/Features/Editor/Comments/Views/BrowserContentWithCommentsPanel.swift"],
  [agent_cli, "#{base}/Features/AgentCLI/CLICommandRouterCommentsHandlers.swift"],
]

entries.each do |group, abs|
  abort("missing source file: #{abs}") unless File.exist?(abs)
  add_swift(group, main_target, abs)
end

# --- Tests target registration ---

unit_test_target = project.targets.find { |t| t.name == 'CrispyVibesUnitTests' }
abort('CrispyVibesUnitTests target not found') unless unit_test_target

# Walk to the existing tests/unit/Features/Editor group and add Comments subgroup.
tests_root = project.main_group.groups.find { |g| g.display_name == 'tests' || g.path == 'tests' }
unless tests_root
  tests_root = project.main_group.new_group('tests', 'tests')
end
unit_group = child(tests_root, 'unit')
unit_features = child(unit_group, 'Features')
unit_editor = child(unit_features, 'Editor')
unit_comments = child(unit_editor, 'Comments')

test_base = File.expand_path('../projects/crispyvibes/tests/unit', __dir__)
test_entries = [
  [unit_comments, "#{test_base}/Features/Editor/Comments/CommentAnchorRelocatorTests.swift"],
]

test_entries.each do |group, abs|
  abort("missing test file: #{abs}") unless File.exist?(abs)
  add_swift(group, unit_test_target, abs)
end

project.save
puts 'pbxproj updated successfully.'
