import SwiftUI

/// Top-right panel: Auto-checking acceptance criteria checklist
struct AcceptanceCriteriaView: View {
  var session: AgentSession
  @State private var newCriterionText = ""

  private var completedCount: Int {
    session.criteria.filter(\.isCompleted).count
  }

  private var progress: Double {
    guard !session.criteria.isEmpty else { return 0 }
    return Double(completedCount) / Double(session.criteria.count)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "checklist")
          .foregroundColor(.orange)
        Text("Acceptance Criteria")
          .font(.headline)
        Spacer()
        if !session.criteria.isEmpty {
          Text("\(completedCount)/\(session.criteria.count)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(completedCount == session.criteria.count ? .green : .secondary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      // Progress bar
      if !session.criteria.isEmpty {
        ProgressView(value: progress)
          .tint(completedCount == session.criteria.count ? .green : .orange)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
      }

      if session.criteria.isEmpty {
        emptyState
      } else {
        criteriaList
      }

      Divider()

      // Add criterion input
      HStack(spacing: 6) {
        TextField("Add criterion...", text: $newCriterionText)
          .textFieldStyle(.roundedBorder)
          .font(.caption)
          .onSubmit { addCriterion() }

        Button(action: addCriterion) {
          Image(systemName: "plus.circle.fill")
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.borderless)
        .disabled(newCriterionText.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Spacer()
      Image(systemName: "checkmark.circle.badge.questionmark")
        .font(.system(size: 24))
        .foregroundColor(.secondary)
      Text("No criteria yet")
        .font(.caption)
        .foregroundColor(.secondary)
      Text("Add manually or wait for agent to report them")
        .font(.caption2)
        .foregroundColor(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var criteriaList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(session.criteria) { criterion in
          CriterionRow(criterion: criterion) {
            session.markCriterion(id: criterion.id, completed: !criterion.isCompleted)
            if !criterion.isCompleted {
              NSHapticFeedbackManager.defaultPerformer.perform(
                .levelChange, performanceTime: .default)
            }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
    }
  }

  private func addCriterion() {
    let text = newCriterionText.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    session.criteria.append(AcceptanceCriterion(text: text))
    newCriterionText = ""
  }
}

// MARK: - Criterion Row

struct CriterionRow: View {
  let criterion: AcceptanceCriterion
  let onToggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Button(action: onToggle) {
        Image(systemName: criterion.isCompleted ? "checkmark.circle.fill" : "circle")
          .foregroundColor(criterion.isCompleted ? .green : .secondary)
          .font(.body)
      }
      .buttonStyle(.borderless)

      Text(criterion.text)
        .font(.callout)
        .foregroundColor(criterion.isCompleted ? .secondary : .primary)
        .strikethrough(criterion.isCompleted)
        .lineLimit(3)
        .textSelection(.enabled)

      Spacer()
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(criterion.isCompleted ? Color.green.opacity(0.05) : Color.clear)
    )
    .animation(.easeInOut(duration: 0.2), value: criterion.isCompleted)
  }
}
