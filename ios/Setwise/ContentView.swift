import PhotosUI
import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var store: WorkoutStore
    @StateObject private var signIn = GoogleSignIn()
    @State private var showingAddExercise = false

    var body: some View {
        NavigationStack {
            Group {
                if store.hasSession() { workoutScreen }
                else { signInScreen }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Setwise", systemImage: "dumbbell.fill")
                        .font(.headline)
                        .labelStyle(.titleAndIcon)
                }
                if store.hasSession() {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Refresh workouts", systemImage: "arrow.clockwise") { Task { await store.load() } }
                            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { store.signOut() }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .task { await store.load() }
            .alert("Setwise", isPresented: Binding(get: { store.errorMessage != nil || signIn.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil; signIn.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil; signIn.errorMessage = nil }
            } message: { Text(store.errorMessage ?? signIn.errorMessage ?? "") }
            .sheet(isPresented: $showingAddExercise) { AddExerciseSheet(store: store) }
        }
        .tint(Color(red: 0.16, green: 0.48, blue: 0.36))
    }

    private var signInScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "dumbbell.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("Your training, together").font(.title2.bold())
            Text("Sign in with the Google account connected to your Setwise workouts. Your session is stored securely on this iPhone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 28)
            Button {
                signIn.signIn { store.saveSessionToken($0) }
            } label: {
                Label(signIn.isSigningIn ? "Opening Google…" : "Continue with Google", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent).padding(.horizontal, 32).disabled(signIn.isSigningIn)
            Text("Workout changes stay on this device until you tap Complete this day.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var workoutScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let last = store.lastCompleted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Last completed").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(last.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                daySelector
                if let start = store.sessionStartedAt {
                    workoutTimer(startedAt: start)
                }
                HStack(spacing: 8) {
                    Circle().fill(store.isSaving ? .orange : .green).frame(width: 7, height: 7)
                    Text(store.statusMessage).font(.footnote).foregroundStyle(.secondary)
                }
                if store.isLoading { ProgressView("Loading workouts…").frame(maxWidth: .infinity).padding() }
                let exercises = store.exercisesForUI()
                if exercises.isEmpty {
                    ContentUnavailableView("No exercises for this day", systemImage: "dumbbell", description: Text("Add exercises to start your workout."))
                }
                ForEach(exercises) { exercise in ExerciseCard(exercise: exercise, previous: store.previousSets(for: exercise.id), store: store) }
                Button { showingAddExercise = true } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.bordered)

                HStack(spacing: 10) {
                    Button { store.beginWorkout() } label: {
                        Label("Start workout", systemImage: "timer")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }.buttonStyle(.bordered).disabled(store.sessionStartedAt != nil)
                    Button { Task { await store.completeDay() } } label: {
                        Label(store.isSaving ? "Saving…" : "Complete this day", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }.buttonStyle(.borderedProminent).disabled(store.isSaving || exercises.isEmpty)
                }
                Text("Completion syncs your workout to your account and asks permission to save a strength workout in Apple Health.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func workoutTimer(startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            let hours = elapsed / 3600
            let minutes = (elapsed % 3600) / 60
            let seconds = elapsed % 60
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("WORKOUT IN PROGRESS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds))
                        .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                }
                Spacer()
                Text("Started")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var daySelector: some View {
        HStack {
            Button { store.selectDay(offset: -1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 42) }.buttonStyle(.bordered)
            Spacer()
            VStack(spacing: 3) {
                Text(store.selectedDate.formatted(.dateTime.weekday(.wide))).font(.title3.bold())
                Text(store.selectedDate.formatted(.dateTime.month(.wide).day().year())).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.selectDay(offset: 1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 42) }.buttonStyle(.bordered)
        }
    }
}

private struct ExerciseCard: View {
    let exercise: WorkoutExercise
    let previous: [WorkoutSet]
    @ObservedObject var store: WorkoutStore
    @State private var photoItem: PhotosPickerItem?
    @State private var videoText = ""
    @State private var confirmRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                if let image = decodedPhoto(exercise.photo) { Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 42).clipShape(Circle()) }
                else { Image(systemName: "figure.strengthtraining.traditional").font(.title2).foregroundStyle(.green).frame(width: 42, height: 42).background(.green.opacity(0.12), in: Circle()) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name).font(.headline)
                    if !exercise.muscle.isEmpty { Text(exercise.muscle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                let currentScore = exercise.sets.map { (Double($0.reps) ?? 0) * (Double($0.weight) ?? 0) }.max() ?? 0
                if currentScore > 0 {
                    Text(currentScore >= store.bestScore(exercise.id) ? "NEW BEST" : "\(Int(currentScore)) PTS")
                        .font(.caption2.bold()).foregroundStyle(currentScore >= store.bestScore(exercise.id) ? .green : .secondary)
                }
                if let url = URL(string: exercise.videoURL), ["https", "http"].contains(url.scheme) {
                    Link(destination: url) { Image(systemName: "play.rectangle").font(.title3) }
                }
            }
            HStack(spacing: 9) {
                Text("SET").frame(width: 30)
                Text("REPS").frame(maxWidth: .infinity)
                Text("KG").frame(maxWidth: .infinity)
                Text("DONE").frame(width: 40)
                Color.clear.frame(width: 20)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(exercise.sets) { set in
                HStack(spacing: 9) {
                    Text("\(set.id + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30)
                    NumericEntry(value: set.reps, placeholder: previous.indices.contains(set.id) ? previous[set.id].reps : "", keyboard: .numberPad) { store.updateSet(exerciseID: exercise.id, setIndex: set.id, field: "reps", value: $0) }
                    NumericEntry(value: set.weight, placeholder: previous.indices.contains(set.id) ? previous[set.id].weight : "", keyboard: .decimalPad) { store.updateSet(exerciseID: exercise.id, setIndex: set.id, field: "weight", value: $0) }
                    Button { store.updateSet(exerciseID: exercise.id, setIndex: set.id, field: "done", value: !set.done) } label: {
                        Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(set.done ? .green : .secondary)
                    }.frame(width: 40)
                    if set.id >= 3 {
                        Button(role: .destructive) { store.removeSet(exerciseID: exercise.id, setIndex: set.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    } else { Color.clear.frame(width: 20) }
                }
                if previous.indices.contains(set.id) {
                    Text("Previous · \(previous[set.id].reps) reps × \(previous[set.id].weight) kg").font(.caption2).foregroundStyle(.secondary).padding(.leading, 39)
                }
            }
            Button { store.addSet(exerciseID: exercise.id) } label: { Label("Add set", systemImage: "plus") }.font(.footnote)
            let history = store.progress(exercise.id)
            if !history.isEmpty {
                Chart(history) { sample in
                    LineMark(x: .value("Date", sample.date), y: .value("Weight", sample.weight)).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", sample.date), y: .value("Weight", sample.weight)).symbolSize(22)
                }
                .chartYAxisLabel("kg")
                .frame(height: 100)
            }
            TextField("One-line note for this exercise…", text: Binding(get: { store.note(for: exercise.id) }, set: { store.updateNote(exerciseID: exercise.id, note: $0) }))
                .textFieldStyle(.roundedBorder)
            if let previousNote = store.previousNote(for: exercise.id) {
                Text("Previous note · \(previousNote)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) { Label(exercise.photo.isEmpty ? "Add photo" : "Change photo", systemImage: "photo") }.font(.footnote)
                TextField("Video / how-to URL", text: $videoText).font(.footnote).textInputAutocapitalization(.never).keyboardType(.URL)
            }
            Button("Remove exercise", role: .destructive) { confirmRemoval = true }.font(.footnote)
                .confirmationDialog("Remove \(exercise.name)?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                    Button("Remove exercise", role: .destructive) { store.removeExercise(id: exercise.id) }
                    Button("Cancel", role: .cancel) { }
                }
            .onAppear { videoText = exercise.videoURL }
            .onChange(of: videoText) { _, text in store.updateExercise(exerciseID: exercise.id, field: "videoUrl", value: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        let scale = min(1, 360 / max(image.size.width, image.size.height))
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        let renderer = UIGraphicsImageRenderer(size: size)
                        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                        if let jpg = resized.jpegData(compressionQuality: 0.72) { store.updateExercise(exerciseID: exercise.id, field: "photo", value: "data:image/jpeg;base64,\(jpg.base64EncodedString())") }
                    }
                }
            }
        }
        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.06)))
    }

    private func decodedPhoto(_ source: String) -> UIImage? {
        guard let comma = source.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(source[source.index(after: comma)...])).flatMap(UIImage.init(data:))
    }
}

private struct NumericEntry: View {
    let value: String
    let placeholder: String
    let keyboard: UIKeyboardType
    let changed: (String) -> Void
    var body: some View {
        TextField(placeholder, text: Binding(get: { value }, set: changed))
            .keyboardType(keyboard).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
    }
}

private struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: WorkoutStore
    @State private var name = ""
    @State private var muscle = ""
    @State private var video = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                TextField("Body part", text: $muscle)
                TextField("Video / how-to URL", text: $video).textInputAutocapitalization(.never).keyboardType(.URL)
                Text("New exercises start with 3 empty sets. Prior exercise photo and video links are reused when available.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { store.addExercise(name: name, muscle: muscle, videoURL: video, photo: ""); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
