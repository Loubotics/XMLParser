# == Schema Information
#
# Table name: favourites
#
#  id         :integer          not null, primary key
#  station    :string(255)
#  user_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  name       :string(255)
#

class Favourite < ActiveRecord::Base
  attr_accessible :station, :user_id, :name
  belongs_to :user
end
