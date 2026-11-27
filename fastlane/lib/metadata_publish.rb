# Publishing policy kept separate from fastlane so target checks can be tested offline.
module MetadataPublish
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze

  def self.validate_target!(version, requested)
    raise ArgumentError, "Pass app_version:<version> explicitly" if requested.to_s.strip.empty?
    unless version && version.version_string == requested
      raise ArgumentError, "Create/select editable iOS version #{requested} in App Store Connect first; no version will be created or renamed"
    end
    unless EDITABLE_STATES.include?(version.app_version_state)
      raise ArgumentError, "Version #{requested} is #{version.app_version_state}; metadata publishing requires an editable version"
    end
  end

  def self.options(identifier, version, path)
    {
      app_identifier: identifier,
      app_version: version,
      platform: "ios",
      metadata_path: path,
      skip_app_version_update: true,
      edit_live: false,
      skip_binary_upload: true,
      skip_screenshots: true,
      submit_for_review: false,
      reject_if_possible: false,
      run_precheck_before_submit: false,
      force: true
    }
  end
end
