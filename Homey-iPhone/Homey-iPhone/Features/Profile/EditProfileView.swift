import PhotosUI
import SwiftUI
import UIKit

struct EditProfileView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let onSuccess: (String) -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var displayName = ""
    @State private var original = ProfileValues(firstName: "", lastName: "", displayName: "")
    @State private var isDisplayNameCustomized = false
    @State private var isUpdatingDisplayName = false
    @State private var didPopulate = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var values: ProfileValues { ProfileValues(firstName: firstName, lastName: lastName, displayName: displayName) }
    private var hasChanges: Bool { values != original }
    private var validationMessage: String? {
        if values.firstName.isEmpty { return "Enter your first name." }
        if values.lastName.isEmpty { return "Enter your last name." }
        if values.displayName.isEmpty { return "Enter a display name." }
        return nil
    }
    private var isBusy: Bool { session.authentication.isLoading || session.authentication.isUploadingAvatar }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        avatarCard
                        informationCard
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isBusy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!hasChanges || validationMessage != nil || isBusy)
                }
            }
        }
        .task { populateIfNeeded() }
        .onChange(of: firstName) { _, _ in updateGeneratedDisplayNameIfNeeded() }
        .onChange(of: lastName) { _, _ in updateGeneratedDisplayNameIfNeeded() }
        .onChange(of: displayName) { _, value in handleDisplayNameChange(value) }
        .confirmationDialog("Profile Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showingCamera = true }
            }
            Button("Choose from Photo Library") { showingPhotoPicker = true }
            if session.currentUser?.avatarURL != nil {
                Button("Remove Photo", role: .destructive) { Task { await removePhoto() } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhoto, matching: .images)
        .sheet(isPresented: $showingCamera) {
            ProfileCameraPicker { image in Task { await upload(image) } }.ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, item in Task { await loadPhoto(item) } }
    }

    private var avatarCard: some View {
        VStack(spacing: 12) {
            Button {
                guard !isBusy else { return }
                showingPhotoOptions = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(profile: session.currentUser, size: 112, isLoading: session.authentication.isUploadingAvatar)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(HomeyColors.primary, in: Circle())
                        .overlay { Circle().stroke(Color.white, lineWidth: 3) }
                }
            }
            .buttonStyle(.plain).disabled(isBusy).accessibilityLabel("Change profile photo")
            Text("Change Photo").font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.primary)
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(HomeyColors.success)
            }
        }
        .frame(maxWidth: .infinity).homeyCard()
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profile Information").font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
                Text("These details apply across every Home you belong to.").font(.caption).foregroundStyle(HomeyColors.secondaryText)
            }
            profileField("First Name", text: $firstName, contentType: .givenName)
            profileField("Last Name", text: $lastName, contentType: .familyName)
            profileField("Display Name", text: $displayName, contentType: .name)

            VStack(alignment: .leading, spacing: 7) {
                Text("Email").font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                HStack {
                    Text(session.currentUser?.email ?? "Email unavailable").font(.subheadline).foregroundStyle(HomeyColors.text).lineLimit(1)
                    Spacer()
                    Text("Read Only").font(.caption2.bold()).foregroundStyle(HomeyColors.secondaryText)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(HomeyColors.border.opacity(0.18), in: Capsule())
                }
                .padding(.horizontal, 15).frame(minHeight: 52).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                .overlay { RoundedRectangle(cornerRadius: HomeyCornerRadius.field).stroke(HomeyColors.border) }
            }

            if hasChanges, let validationMessage { HomeyErrorView(message: validationMessage) }
            if let errorMessage { HomeyErrorView(message: errorMessage) }

            Button { Task { await save() } } label: {
                if session.authentication.isLoading { HStack { ProgressView().tint(.white); Text("Saving…") } }
                else { Text("Save Changes") }
            }
            .buttonStyle(HomeyButtonStyle())
            .disabled(!hasChanges || validationMessage != nil || isBusy)
            .opacity(hasChanges && validationMessage == nil && !isBusy ? 1 : 0.55)
        }
        .homeyCard()
    }

    private func profileField(_ label: String, text: Binding<String>, contentType: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
            TextField(label, text: text).textContentType(contentType).textInputAutocapitalization(.words).autocorrectionDisabled().homeyTextField()
        }
    }

    private func populateIfNeeded() {
        guard !didPopulate, let profile = session.currentUser else { return }
        let loaded = ProfileValues(firstName: profile.firstName ?? "", lastName: profile.lastName ?? "", displayName: profile.displayName ?? "")
        firstName = loaded.firstName
        lastName = loaded.lastName
        let generated = ProfileNameFormatter.generatedDisplayName(firstName: loaded.firstName, lastName: loaded.lastName)
        isDisplayNameCustomized = !loaded.displayName.isEmpty && loaded.displayName != generated
        setDisplayName(loaded.displayName.isEmpty ? generated : loaded.displayName)
        original = ProfileValues(firstName: firstName, lastName: lastName, displayName: displayName)
        didPopulate = true
    }

    private func save() async {
        guard hasChanges, validationMessage == nil, !isBusy else { return }
        errorMessage = nil
        if await session.authentication.updateCurrentUserProfile(firstName: values.firstName, lastName: values.lastName, displayName: values.displayName) {
            await propagateProfileChange()
            onSuccess("Profile updated.")
            dismiss()
        } else {
            errorMessage = session.authentication.errorMessage ?? "We couldn't update your profile."
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = "We couldn't read that image. Please choose another photo."
                return
            }
            await upload(image)
        } catch {
            errorMessage = "We couldn't read that image. Please choose another photo."
        }
    }

    private func upload(_ image: UIImage) async {
        guard let data = ProfileAvatarImageProcessor.jpegData(from: image) else {
            errorMessage = "We couldn't prepare that image. Please choose another photo."
            return
        }
        errorMessage = nil
        statusMessage = nil
        if await session.authentication.uploadCurrentUserAvatar(imageData: data) {
            await propagateProfileChange()
            statusMessage = "Profile photo updated."
            onSuccess("Profile photo updated.")
        } else {
            errorMessage = session.authentication.errorMessage ?? "We couldn't update your profile photo."
        }
    }

    private func removePhoto() async {
        errorMessage = nil
        statusMessage = nil
        if await session.authentication.removeCurrentUserAvatar() {
            await propagateProfileChange()
            statusMessage = "Profile photo removed."
            onSuccess("Profile photo removed.")
        } else {
            errorMessage = session.authentication.errorMessage ?? "We couldn't remove your profile photo."
        }
    }

    private func propagateProfileChange() async {
        if let home = session.activeHome, let userID = session.currentUser?.id {
            await session.homes.loadMembers(homeID: home.id, currentUserID: userID, forceRefresh: true)
        }
        NotificationCenter.default.post(name: .homeyProfileDidChange, object: session.currentUser?.id)
        NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
    }

    private func updateGeneratedDisplayNameIfNeeded() {
        guard !isDisplayNameCustomized else { return }
        setDisplayName(ProfileNameFormatter.generatedDisplayName(firstName: firstName, lastName: lastName))
    }

    private func handleDisplayNameChange(_ value: String) {
        guard !isUpdatingDisplayName else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isDisplayNameCustomized = false
            updateGeneratedDisplayNameIfNeeded()
        } else {
            isDisplayNameCustomized = trimmed != ProfileNameFormatter.generatedDisplayName(firstName: firstName, lastName: lastName)
        }
    }

    private func setDisplayName(_ value: String) {
        isUpdatingDisplayName = true
        displayName = value
        isUpdatingDisplayName = false
    }
}

private struct ProfileValues: Equatable {
    let firstName: String
    let lastName: String
    let displayName: String
    init(firstName: String, lastName: String, displayName: String) {
        self.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ProfileCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ProfileCameraPicker
        init(parent: ProfileCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { parent.onImagePicked(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

private enum ProfileAvatarImageProcessor {
    static func jpegData(from image: UIImage, targetPixelSize: CGFloat = 512, compressionQuality: CGFloat = 0.82) -> Data? {
        let normalized = normalized(image)
        let square = squareCrop(normalized)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: targetPixelSize, height: targetPixelSize)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            square.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: compressionQuality)
    }

    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        return UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private static func squareCrop(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let rect = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let scaled = CGRect(x: rect.origin.x * image.scale, y: rect.origin.y * image.scale, width: rect.width * image.scale, height: rect.height * image.scale)
        guard let cropped = image.cgImage?.cropping(to: scaled) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
