require "minitest/autorun"
require_relative "../lib/metadata_publish"

class MetadataPublishTest < Minitest::Test
  Version = Struct.new(:version_string, :app_version_state)

  def test_requires_explicit_existing_matching_version
    [nil, Version.new("1.1", "PREPARE_FOR_SUBMISSION")].each do |version|
      assert_raises(ArgumentError) { MetadataPublish.validate_target!(version, "1.2") }
    end
    assert_raises(ArgumentError) { MetadataPublish.validate_target!(nil, "") }
  end

  def test_rejects_live_and_review_versions
    %w[READY_FOR_DISTRIBUTION WAITING_FOR_REVIEW IN_REVIEW PENDING_DEVELOPER_RELEASE].each do |state|
      assert_raises(ArgumentError) do
        MetadataPublish.validate_target!(Version.new("1.2", state), "1.2")
      end
    end
    MetadataPublish.validate_target!(Version.new("1.2", "PREPARE_FOR_SUBMISSION"), "1.2")
  end

  def test_upload_options_do_not_change_version_or_submit
    options = MetadataPublish.options("com.jimmyho.checklists", "1.2", "staged")
    assert options[:skip_binary_upload]
    assert options[:skip_screenshots]
    assert options[:skip_app_version_update]
    refute options[:submit_for_review]
    refute options[:reject_if_possible]
    refute options[:edit_live]
    refute options.key?(:automatic_release)
    refute options.key?(:price_tier)
  end
end
