require "rails_helper"

RSpec.describe Comments::CommunityWellnessQuery, type: :query do
  include ActionView::Helpers::DateHelper

  let!(:articles) { create_list(:article, 4) }
  let!(:mod) { create(:user, :trusted) }
  let!(:user1) { create(:user) }
  let!(:user2) { create(:user) }
  let!(:user3) { create(:user) }
  let!(:user4) { create(:user) }
  let!(:user5) { create(:user) }

  # Pre-populate "filler users" that shouldn't appear in results because they
  # don't meet the query criteria: min 2 comments in a week within last 32 weeks
  before do
    # User 3 - only one comment
    create_comment_time_ago(user3.id, 5.days.ago, commentable: articles.sample)

    # User 4 - has 3 comments but doesn't meet criteria bc comments are too old
    create_comment_time_ago(user4.id, 226.days.ago, commentable: articles.sample)
    create_comment_time_ago(user4.id, 227.days.ago, commentable: articles.sample)
    create_comment_time_ago(user4.id, 227.days.ago, commentable: articles.sample)
  end

  context "when multiple users match criteria" do
    before do
      # User 1 - week 1
      create_comment_time_ago(user1.id, 5.days.ago, commentable: articles.sample)
      create_comment_time_ago(user1.id, 6.days.ago, commentable: articles.sample)
      # User 1 - week 2
      create_comment_time_ago(user1.id, 8.days.ago, commentable: articles.sample)
      create_comment_time_ago(user1.id, 11.days.ago, commentable: articles.sample)

      # User 2 - week 1
      create_comment_time_ago(user2.id, 4.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 6.days.ago, commentable: articles.sample)
      # User 1 - week 2
      create_comment_time_ago(user2.id, 9.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 13.days.ago, commentable: articles.sample)
      # User 1 - week 3
      create_comment_time_ago(user2.id, 17.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 17.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 18.days.ago, commentable: articles.sample)

      # User 5 - has 2 comments in the first week but too early to award because
      # comments must be 3 days old or more to give mods time to flag before award
      create_comment_time_ago(user5.id, 2.days.ago, commentable: articles.sample)
      create_comment_time_ago(user5.id, 6.days.ago, commentable: articles.sample)
    end

    it "returns the correct data structure (array of hashes w/ correct keys)" do
      result = described_class.call

      expect(result).to be_instance_of(Array)
      expect(result.count).to eq(3)

      result.each do |hash|
        expect(hash["user_id"]).to be_instance_of(Integer)
        expect(hash["serialized_weeks_ago"]).to be_instance_of(String)
        expect(hash["serialized_comment_counts"]).to be_instance_of(String)
      end
    end

    it "returns users with correct data on their corresponding hash" do
      result = described_class.call

      result_user_ids = result.map { |hash| hash["user_id"] }
      expect(result_user_ids).to contain_exactly(user1.id, user2.id, user5.id)

      index1 = result.index { |hash| hash["user_id"] == user1.id }
      expect(result[index1]["serialized_weeks_ago"]).to eq("1,2")
      expect(result[index1]["serialized_comment_counts"]).to eq("2,2")

      index2 = result.index { |hash| hash["user_id"] == user2.id }
      expect(result[index2]["serialized_weeks_ago"]).to eq("1,2,3")
      expect(result[index2]["serialized_comment_counts"]).to eq("2,2,3")

      # user5 will still appear in the query because it has 2 comments in the
      # week but the count will reflect only those that are 3+ days old
      index5 = result.index { |hash| hash["user_id"] == user5.id }
      expect(result[index5]["serialized_weeks_ago"]).to eq("1")
      expect(result[index5]["serialized_comment_counts"]).to eq("1")
    end
  end

  context "when users match criteria but mod reaction reduces their comment counts" do
    before do
      # User 1 - week 1
      create_comment_time_ago(user1.id, 5.days.ago, commentable: articles.sample, flagged_by: mod)
      create_comment_time_ago(user1.id, 6.days.ago, commentable: articles.sample)
      # User 1 - week 2
      create_comment_time_ago(user1.id, 8.days.ago, commentable: articles.sample)
      create_comment_time_ago(user1.id, 11.days.ago, commentable: articles.sample)

      # User 2 - week 1
      create_comment_time_ago(user2.id, 4.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 6.days.ago, commentable: articles.sample)
      # User 1 - week 2
      create_comment_time_ago(user2.id, 9.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 13.days.ago, commentable: articles.sample, flagged_by: mod)
      # User 1 - week 3
      create_comment_time_ago(user2.id, 17.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 17.days.ago, commentable: articles.sample)
      create_comment_time_ago(user2.id, 18.days.ago, commentable: articles.sample)
    end

    it "matches the correct comment count for each week in result hash" do
      result = described_class.call

      result_user_ids = result.map { |hash| hash["user_id"] }
      # Result includes both users because they have > 1 comment per week
      expect(result_user_ids).to contain_exactly(user1.id, user2.id)

      # user1 must have `1` in first week comment count because one of their 2
      # comments is flagged by a moderator
      index1 = result.index { |hash| hash["user_id"] == user1.id }
      expect(result[index1]["serialized_weeks_ago"]).to eq("1,2")
      expect(result[index1]["serialized_comment_counts"]).to eq("1,2")

      # Second
      index2 = result.index { |hash| hash["user_id"] == user2.id }
      expect(result[index2]["serialized_weeks_ago"]).to eq("1,2,3")
      expect(result[index2]["serialized_comment_counts"]).to eq("2,1,3")
    end
  end
end
