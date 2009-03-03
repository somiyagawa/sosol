class Article < ActiveRecord::Base
  include ArticlesHelper
  
  has_many :comments
  belongs_to :user
  belongs_to :master_article
  belongs_to :board
  
  #article types
  has_one :meta
  has_one :transcription
  has_one :translation
   
  # has_many :events
  validates_presence_of :content
  
  # validate :must_be_valid_xml
  # validate :must_be_valid_epidoc
  
#edit_article_path(article)
  def get_category_obj()
    if self.meta
      obj = self.meta
    elsif self.transcription
      obj = self.transcription
    elsif self.translation
      obj = self.translation           
    else
      obj = self
    end
    
    obj   
  end
  

  
  def must_be_valid_xml
    # errors.add_to_base("Content must be valid XML") unless (valid_xml?(content) != nil)
  end

  def must_be_valid_epidoc
    errors.add_to_base("Content must be valid EpiDoc") unless valid_epidoc?(content)
  end
  
end
