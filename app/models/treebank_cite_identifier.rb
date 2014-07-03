class TreebankCiteIdentifier < CiteIdentifier   
  include OacHelper

  FRIENDLY_NAME = "Treebank Annotation"
  PATH_PREFIX="CITE_TREEBANK_XML"
  FILE_TYPE="tb.xml"
  ANNOTATION_TITLE = "Treebank Annotation"
  TEMPLATE = "template"
  NS_DCAM = "http://purl.org/dc/dcam/"
  NS_TREEBANK = "http://nlp.perseus.tufts.edu/syntax/treebank/1.5"
  NS_RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"


  
  # TODO Validator depends upon treebank format
  XML_VALIDATOR = JRubyXML::PerseusTreebankValidator
  
  # Overrides Identifier#set_content to make sure content is preprocessed first
  # - *Args*  :
  #   - +content+ -> the XML you want committed to the repository
  #   - +options+ -> hash of options to pass to repository (ex. - :comment, :actor)
  # - *Returns* :
  #   - a String of the SHA1 of the commit
  def set_content(content, options = {})
    content = preprocess(content)
    super
  end
  
  def titleize
    title = self.name
    # TODO should say Treebank on Target URI
    t = REXML::Document.new(self.xml_content).root
    # we shouldn't really ever get here without content
    # but if we do, it's better not to throw an error
    if (t)
      f = REXML::XPath.first(t,"sentence")
      l = REXML::XPath.first(t,"sentence[last()]")
      if (f)
        urn = f.attributes['document_id']
        if (urn != '')
          title = "Treebank of #{urn}"
        end
        from = f.attributes['subdoc']
        if (from != '')
          title = title + ":#{from}"  
        end
        if (l)
          to = l.attributes['subdoc']
          if (to != '' && from != to)
            title = title + "-#{to}"
          end
        end
      end
    end
    return title
  end
  
  def toXmlString xmlObject
    formatter = PrettySsime.new
    formatter.compact = true
    formatter.width = 2**32
    modified_xml_content = ''
    formatter.write xmlObject, modified_xml_content
    modified_xml_content
  end
  
  # initialization method for a new version of an existing Annotation Object
  # adds the creator as a top-level annotator and creates/updates the date
  # @param a_content the original content
  # @return the updated content
  def init_version_content(a_content)
    treebank = REXML::Document.new(a_content).root
    treebank.delete_element("date")
    date = REXML::Element.new("date")
    date.add_text(Time.new.inspect)
    treebank.insert_before("*[1]",date)
    creator_uri = make_annotator_uri
    xpath = "annotator/uri"
    all_annotators = REXML::XPath.match(treebank, xpath)
    add = true
    all_annotators.each do |ann|
      if  ann == creator_uri
        add = false
      end
    end
    if (add)
      annotator = REXML::Element.new("annotator")
      short = REXML::Element.new("short")
      short.add_text(self.publication.creator.name)
      persname = REXML::Element.new("name")
      persname.add_text(self.publication.creator.human_name)
      address = REXML::Element.new("address")
      address.add_text(self.publication.creator.email)
      uri = REXML::Element.new("uri")
      uri.add_text(creator_uri)
      annotator.add_element(short)
      annotator.add_element(persname)
      annotator.add_element(address)
      annotator.add_element(uri)
      treebank.insert_before("sentence[1]",annotator)
    end
    toXmlString treebank
  end
  
  # Initializes a treebank template
  # First looks in the repository to see if we already have a template
  # for the requested URN target. If so, we just use that. Otherwise
  # we send a job to the annotation service to create one
  # @param [String] a_value is the initialization value - in this case the target urn 
  def init_content(a_value)
    template = self.content

    if (! a_value.nil? && a_value.length == 1) 
      init_value = a_value[0].to_s
      begin
        urn_value = init_value.match(/^https?:.*?(urn:cts:.*)$/).captures[0]
        urn_obj = CTS::CTSLib.urnObj(urn_value)
        unless (urn_obj.nil?)
          base_uri = init_value.match(/^(http?:\/\/.*?)\/urn:cts.*$/).captures[0]
          template_path = path_for_target(TEMPLATE,base_uri,urn_obj)
          template = self.publication.repository.get_file_from_branch(template_path, 'master') 
        end
      rescue Exception => e
        # if we get an exception it might be an invalid urn or it might be something that
        # isn't a urn - if it's a uri we try to retrieve the content 
        if (a_value =~ /^https?:/)
          begin
              svc_params =
                { :text_uri => a_value, 
                  :template_format => 'Perseus',
                  :mime_type => 'text/xml', # TODO - mime_type and lang should be auto-detected by svc
                  :lang => 'grc', 
                  :wait => 'true' # TODO we need to support async
                }
              response = Services::Manager.send_request(self.publication,'annotation/template', svc_params)
              template = OacHelper.get_body_xml(response)
              # TODO support call to Morphology Service ?
          rescue
            raise "Invalid treebank content at #{a_value}"
          end
          # not a cts urn, just assume we have to create a new template
          raise "Not a URN"
        else 
          # otherwise raise an error
          raise e
        end
      end
    end
    if (template.nil?)
      raise "Unable to create template for #{a_value.inspect}"    
    end

    template_init = init_version_content(template)
    self.set_xml_content(template_init, :comment => 'Initializing Content')
  end
  
  # Path for treebank file for target text
  # @param [String] a_type (template or data) 
  # @param [String] a_base_uri the base uri
  # @param [JCtsUrn] a_target_urn
  # @return [String] the repository path
  def path_for_target(a_type,a_base_uri,a_target_urn)
    uri = a_base_uri.gsub(/^http?:\/\//, '')
    parts = []
    #  PATH_PREFIX/type/uri/namespace/textgroup/work/textgroup.work.edition.passage.FILE_TYPE
    parts << PATH_PREFIX
    parts << a_type
    parts << uri
    tgparts = a_target_urn.getTextGroup().split(/:/)
    work  = a_target_urn.getWork(false)
    parts << tgparts[0]
    parts << tgparts[1]
    parts << work
    file_parts = []
    file_parts << tgparts[1]
    file_parts << work
    file_parts <<  a_target_urn.getVersion(false)
    if (a_target_urn.passageComponent)
      file_parts << a_target_urn.getPassage(100)
    end
    file_parts << FILE_TYPE
    parts << file_parts.join(".")
    File.join(parts)
  end
  
  # get a sentence
  # @param [String] a_id the sentence id
  # @return [String] the sentence xml 
  def sentence(a_id)
    t = REXML::Document.new(self.xml_content)
    s = REXML::XPath.first(t,"/treebank/sentence[@id=#{a_id}]")
    toXmlString s
  end
  
  # get descriptive info for a treebank file
  def api_info(urls)
    # TODO eventually this will be customized per user/file - for now return the default
    template_path = File.join(Rails.root, ['data','templates'],
                              "treebank-desc-#{self.format}.xml.erb")
    template = ERB.new(File.new(template_path).read, nil, '-')
    
    format = self.format
    lang = self.language
    size = self.size
    direction = self.direction
    return template.result(binding)
  end
  
  # get the format for the treebank file
  def format
    t = REXML::Document.new(self.xml_content)
    REXML::XPath.first(t,"/treebank/@format").to_s
  end
  
  
  # get the language for the treebank file
  def language
    t = REXML::Document.new(self.xml_content)
    REXML::XPath.first(t,"/treebank/@xml:lang").to_s
  end
  
  # get the number of sentences in the treebank file
  def size
    t = REXML::Document.new(self.xml_content)
    REXML::XPath.match(t,"/treebank/sentence").size.to_s
  end
  
   # get the direction of text in the treebank file
  def direction
    t = REXML::Document.new(self.xml_content)
    d = REXML::XPath.first(t,"/treebank/@direction").to_s
    return d == '' ? 'ltr' : d
  end
  
  # api_get responds to a call from the data management api controller
  # @param [String] a_query if not nil, means use the query to 
  #                         return part of the item
  # TODO the query should really be an XPath 
  def api_get(a_query)
    qmatch = /^s=(\d+)$/.match(a_query)
    if (qmatch.nil?)
      return self.xml_content
    else
      return sentence(qmatch[1])
    end
  end
  
  def self.api_parse_post_for_identifier(a_post)
    oacxml = REXML::Document.new(a_post).root
    urn = REXML::XPath.first(oacxml,'//dcam:memberOf',{"dcam" => NS_DCAM})
    if (urn)
      return urn.attributes['rdf:resource']
    else
      raise "Unspecified Collection"
    end
  end
  
  def self.api_create(a_publication,a_agent,a_body,a_comment)
    urn = self.api_parse_post_for_identifier(a_body)
    temp_id = self.new(:name => self.next_object_identifier(urn))
    temp_id.publication = a_publication 
    if (! temp_id.collection_exists?)
      raise "Unregistered CITE Collection for #{urn}"
    end
    temp_id.save!
    oacxml = REXML::Document.new(a_body).root
    treebank = REXML::XPath.first(oacxml,'//tb:treebank',{"tb" => NS_TREEBANK})
    if (!treebank)
      # try without the namespace
      # this is actually all that's currently supported - eventually we want to 
      # require a namespace but that requires a new version of the schema
      treebank = REXML::XPath.first(oacxml,'//treebank')
    end 
    formatter = PrettySsime.new
    formatter.compact = true
    formatter.width = 2**32
    content = ''
    formatter.write treebank, content
    temp_id.set_content(content, :comment => a_comment)
    template_init = temp_id.init_version_content(content)
    temp_id.set_xml_content(template_init, :comment => 'Initializing Content')
    return temp_id
  end
  
  # api_update responds to a call from the data management api controller
  def api_update(a_agent,a_query,a_body,a_comment)
    qmatch = /^s=(\d+)$/.match(a_query)
    if (qmatch && qmatch.size == 2)
      return self.update_sentence(qmatch[1],a_body,a_comment)
    else
      # if no query, assume it's an entire document
      return self.update_document(a_body,a_comment)
    end
  end
 
  def update_document(a_body,a_comment) 
    xml = REXML::Document.new(a_body).root
    updated = toXmlString xml
    self.set_xml_content(updated, :comment => a_comment)
    return updated
  end

  def update_sentence(a_id,a_body,a_comment)
    begin
      s = REXML::Document.new(a_body).root
      t = REXML::Document.new(self.xml_content)
      old = REXML::XPath.first(t,"/treebank/sentence[@id=#{a_id}]")
      if (old.nil?)
        raise "Invalid Sentence Identifier"
      end
      REXML::XPath.each(old,"word") { |w|
         old.delete_element(w) 
      }
      REXML::XPath.each(s,"word") { |w|
         old.add_element(w.clone) 
      }
    rescue Exception => e
      raise e
    end
    updated = toXmlString t
    self.set_xml_content(updated, :comment => a_comment)
    return updated
  end
  
  # Place any actions you always want to perform on  identifier content prior to it being committed in this method
  # - *Args*  :
  #   - +content+ -> TreebankCiteIdentifier XML as string
  def before_commit(content)
    self.preprocess(content)
  end
  
  # Applies the preprocess XSLT to 'content'
  # - *Args*  :
  #   - +content+ -> XML as string
  # - *Returns* :
  #   - modified 'content'
  def preprocess(content)
    # autoadjust sentence numbering
    result = JRubyXML.apply_xsl_transform_catch_messages(
      JRubyXML.stream_from_string(content),
      JRubyXML.stream_from_file(File.join(Rails.root,%w{data xslt cite treebankrenumber.xsl})))  
    # TODO verify against correct schema for format
    if (! result[:messages].nil? && result[:messages].length > 0)
      self[:transform_messages] = result[:messages]
    end
    return result[:content]
  end  
  

  ## method which checks the cite object for an initialization  value
  def is_match?(a_value) 
    has_any_targets = false
   # for a treebank annotation, the match will be on the target urns
    a_value.each do | uri |
      begin
        urn_value = uri.match(/^https?:.*?(urn:cts:.*)$/).captures[0]
        urn_obj = CTS::CTSLib.urnObj(urn_value)
      rescue Exception => e
        # if we get an exception it might be an invalid urn or it might be something that
        # isn't a urn
        if (! uri =~ /urn:cts:/)
          # not a cts urn, just assume we have to create a new template
          Rails.logger.info("Creating treebank file without a URN for #{uri}")
          return false
        else 
          # otherwise raise an error
          raise e
        end
      end

      # TODO need a way to test target uris which aren't CTS urns
      begin
        unless (urn_obj.nil?)
          t = REXML::Document.new(self.xml_content).root
          passage = nil
          begin
            passage = urn_obj.getPassage(100)
          rescue
          end
          if (passage.nil?)
            # if we don't have a passage the match should be on the work only
            work = urn_value;
            match = REXML::XPath.first(t,"sentence[@document_id='#{work}']")
            if (match)
              has_any_targets=true
              break
            end
          elsif (passage)
            work = urn_obj.getUrnWithoutPassage()
            passage.split(/-/).each do | p |
              REXML::XPath.each(t,"sentence[@document_id='#{work}']") do | s |
                unless (s.attributes['subdoc'].match(/^#{p}(\.|$)/).nil?)
                  Rails.logger.info("match on #{work} and #{p} in #{self.id}")
                  has_any_targets = true
                  break
                end
              end
            end 
          else
            # give up for now if we can't parse the cts urn of either the document or subdoc
          end 
        end
      rescue Exception => e
        # if we can't parse the urn we can't test it so just assume it's not a match
        Rails.logger.error(e)
      end
    end
    # TODO compare the requested text urn against the text urns in this treebank document
    return has_any_targets
  end
  
  # preview 
  # outputs the sentence list
  def preview parameters = {}, xsl = nil
    parameters[:s] ||= 1
    JRubyXML.apply_xsl_transform(
      JRubyXML.stream_from_string(content),
      JRubyXML.stream_from_file(File.join(Rails.root,
        xsl ? xsl : %w{data xslt cite treebanklist.xsl})),
        :doc_id => self.id,
        :s => parameters[:s],
        :max => 50, # TODO - make max sentences configurable
        :tool_url => Tools::Manager.tool_config('treebank_editor')[:view_url])  
 end
  
  # edit 
  # outputs the sentence list with sentences linked to editor
  def edit parameters = {}, xsl = nil
    parameters[:s] ||= 1
    JRubyXML.apply_xsl_transform(
      JRubyXML.stream_from_string(content),
      JRubyXML.stream_from_file(File.join(Rails.root,
        xsl ? xsl : %w{data xslt cite treebanklist.xsl})),
        :doc_id => self.id,
        :max => 50, # TODO - make max sentences configurable
        :s => parameters[:s],
        :tool_url => Tools::Manager.tool_config('treebank_editor')[:edit_url])  
  end
  
  
  # need to update the uris to reflect the new name
  def after_rename(options = {})
    annot_uri = SITE_CITE_COLLECTION_NAMESPACE + "/" + self.urn_attribute
    # TODO update uri 
    self.set_xml_content(updated, :comment => 'Update uris to reflect new identifier')
  end
  
  # temporary hack to enable link to Arethusa as an alternate viewer
  def file_preview()
    Tools::Manager.tool_config('treebank_editor')[:file_url].sub('DOC',self.id.to_s)  
  end
end
