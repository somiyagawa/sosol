class EpiTransCTSIdentifier < EpiCTSIdentifier   
  
  PATH_PREFIX = 'CTS_XML_EpiDoc'
  TEMPORARY_COLLECTION = 'TempTrans'
  TEMPORARY_TITLE = 'New Translation'
  
  FRIENDLY_NAME = "Inscription Translation"
  
  IDENTIFIER_NAMESPACE = 'epigraphy_translation'
  
  XML_VALIDATOR = JRubyXML::EpiDocP5Validator
   
  # defined in vendor/plugins/rxsugar/lib/jruby_helper.rb
  acts_as_translation
  
  def self.new_from_template(publication,inventory,urn,pubtype,lang)
    new_identifier = self.new(:name => self.next_temporary_identifier(inventory,urn,pubtype,lang))
    new_identifier.publication = publication
    new_identifier.save!    
    new_identifier.stub_text_structure(lang,new_identifier.id_attribute)     
    return new_identifier
  end
    
  def before_commit(content)
    JRubyXML.apply_xsl_transform(
      JRubyXML.stream_from_string(content),
      JRubyXML.stream_from_file(File.join(Rails.root,
        %w{data xslt translation preprocess.xsl}))
    )
  end
  
  def translation_already_in_language?(lang)
    lang_path = '/TEI/text/body/div[@type = "translation" and @xml:lang = "' + lang + '"]'
    
    doc = REXML::Document.new(self.xml_content)
    result = REXML::XPath.match(doc, lang_path)
    
    if result.length > 0
     return true
    else
      return false
    end
     
  end
  
  def related_text
    self.publication.identifiers.select{|i| (i.class == EpiCTSIdentifier) && !i.is_reprinted?}.last
  end
  
    def stub_text_structure(lang,urn)
    Rails.logger.info("transforming template for #{urn}")
    translation_stub_xml =
      JRubyXML.apply_xsl_transform(
        JRubyXML.stream_from_string(self.related_text.xml_content),
        JRubyXML.stream_from_file(File.join(Rails.root,
          %w{data xslt translation epi_to_translation_xsl.xsl})),
        :lang => lang,
        :urn => urn  
      )
    
    self.set_xml_content(translation_stub_xml, :comment => "New translation stub for @xml:lang='#{lang}'")
  end
    
  def after_rename(options = {})
    if options[:update_header]
      rewritten_xml =
        JRubyXML.apply_xsl_transform(
          JRubyXML.stream_from_string(content),
          JRubyXML.stream_from_file(File.join(Rails.root,
            %w{data xslt translation update_header.xsl})),
          :filename_text => self.to_components.last,
          :title_text => NumbersRDF::NumbersHelper::identifier_to_title([NumbersRDF::NAMESPACE_IDENTIFIER,CTSIdentifier::IDENTIFIER_NAMESPACE,self.to_components.last].join('/'))
        )
    
      self.set_xml_content(rewritten_xml, :comment => "Update header to reflect new identifier '#{self.name}'")
    end
  end
  
  def preview
      JRubyXML.apply_xsl_transform(
      JRubyXML.stream_from_string(self.xml_content),
      JRubyXML.stream_from_file(File.join(Rails.root,
        %w{data xslt pn start-divtrans-portlet.xsl})))
  end
  
end
