include HgvMetaIdentifierHelper
class HgvMetaIdentifiersController < IdentifiersController
  layout 'site'
  before_filter :authorize
  before_filter :prune_params, :only => [:update, :get_date_preview]
  before_filter :complement_params, :only => [:update, :get_date_preview]

  def edit
    find_identifier
    @identifier.get_epidoc_attributes
  end

  def update
    find_identifier
    #exit
    begin
      commit_sha = @identifier.set_epidoc(params[:hgv_meta_identifier], params[:comment])
      expire_publication_cache
      generate_flash_message
    rescue JRubyXML::ParseError => e
      flash[:error] = "Error updating file: #{e.message}. This file was NOT SAVED."
      redirect_to polymorphic_path([@identifier.publication, @identifier],
                                   :action => :edit)
      return
    end
    
    save_comment(params[:comment], commit_sha)
    
    flash[:expansionSet] = params[:expansionSet]

    redirect_to polymorphic_path([@identifier.publication, @identifier],
                                 :action => :edit)
  end
  
  def preview
    find_identifier
    @identifier.get_epidoc_attributes
  end
  
  def complement
    filename = 'geo.xml'
    xpath    = '/TEI/body/list/item/placeName[@type="' + params[:type] + '"][@subtype="' + params[:subtype] + '"][text()="' + params[:value] + '"]/..'
    doc = REXML::Document.new(File.open(File.join(RAILS_ROOT, 'data', 'lookup', filename), 'r'))
    
    @complementer_list = {}
    
    if element = doc.elements[xpath]
      {:provenance_ancientFindspot => ['ancient', 'settlement'], :provenance_modernFindspot => ['modern', 'settlement'], :provenance_nome => ['ancient', 'nome'], :provenance_ancientRegion => ['ancient', 'region']}.each_pair {|key, taxonomy|
        if place = element.elements['placeName[@type="' + taxonomy[0] + '"][@subtype="' + taxonomy[1] + '"]']
          @complementer_list[key] = place.text
        end
      }
    end

    render :layout => false, :json => @complementer_list
    #render :layout => false, :text => @complementer_list.inspect
  end

  def autocomplete
    filename = 'geo.xml'
    xpath    = '/TEI/body/list/item/placeName[@type="' + params[:type] + '"][@subtype="' + params[:subtype] + '"]'
    pattern  = params[params[:key]].gsub(/(\(|\))/, '\\\\\1')
    max      = 10

    @autocompleter_list = []
     

    doc = REXML::Document.new(File.open(File.join(RAILS_ROOT, 'data', 'lookup', filename), 'r'))

    doc.elements.each(xpath) {|element|
      if (@autocompleter_list.length < max) && !@autocompleter_list.include?(element.text) && (element.text =~ Regexp.new('\A' + pattern)) 
        @autocompleter_list[@autocompleter_list.length] = element.text
      end
    }  

    #render :layout => false, :text => @autocompleter_list.inspect
    render :layout => false

  end

  def get_date_preview
    @updates = {}

    [:X, :Y, :Z].each{|dateId|
     index = ('X'[0] - dateId.to_s[0]).abs.to_s
       if params[:hgv_meta_identifier][:textDate][index]
         @updates[dateId] = {
           :when      => params[:hgv_meta_identifier][:textDate][index][:attributes][:when],
           :notBefore => params[:hgv_meta_identifier][:textDate][index][:attributes][:notBefore],
           :notAfter  => params[:hgv_meta_identifier][:textDate][index][:attributes][:notAfter],
           :format   => params[:hgv_meta_identifier][:textDate][index][:value]
         }
       end
    }
        
    respond_to do |format|
      format.js
    end
  end

  protected

    def prune_params

      if params[:hgv_meta_identifier]

        # get rid of empty publication parts
        if params[:hgv_meta_identifier][:publicationExtra]
          params[:hgv_meta_identifier][:publicationExtra].delete_if{|index, extra|
            extra[:value].empty?
          }
        end

        if params[:hgv_meta_identifier][:textDate]
          
          # get rid of empty (invalid) date items
          params[:hgv_meta_identifier][:textDate].delete_if{|index, date|
            date[:c].empty? && date[:y].empty? && !date[:unknown]
          }

          # get rid of unnecessary date attribute @xml:id if there is only one date
          if params[:hgv_meta_identifier][:textDate].length == 1
            params[:hgv_meta_identifier][:textDate]['0'][:attributes][:id] = nil
          end
        end

        # get rid of empty certainties for mentioned dates (X, Y, Z)
        if params[:hgv_meta_identifier]['mentionedDate']
          params[:hgv_meta_identifier]['mentionedDate'].each_pair{|index, date|
            if date['children'] && date['children']['date'] && date['children']['date']['children'] && date['children']['date']['children']['certainty']
              date['children']['date']['children']['certainty'].each_pair{|certainty_index, certainty|
                if certainty['attributes'] && certainty['attributes']['relation'] && certainty['attributes']['relation'].empty?
                  date['children']['date']['children']['certainty'].delete certainty_index
                end
              }
            end
          }
        end

      end

    end

    def complement_params

      if params[:hgv_meta_identifier]

        if params[:hgv_meta_identifier][:textDate]
          params[:hgv_meta_identifier][:textDate].each{|index, date| # for each textDate, i.e. X, Y, Z
            date[:id] = date[:attributes][:id]
            date.delete_if {|k,v| !v.instance_of?(String) || v.empty? }
            params[:hgv_meta_identifier][:textDate][index] = HgvDate.hgvToEpidoc date
          }
        end
        
        if params[:hgv_meta_identifier][:mentionedDate]
          params[:hgv_meta_identifier][:mentionedDate].each{|index, date|
            if date[:children] && date[:children][:date] && date[:children][:date][:attributes]
              date[:children][:date][:value] = HgvFormat.formatDateFromIsoParts(date[:children][:date][:attributes][:when], date[:children][:date][:attributes][:notBefore], date[:children][:date][:attributes][:notAfter], date[:certaintyPicker]) # cl: using date[:certaintyPicker] here is actually a hack
            end
          }
        end

      end

    end

    def generate_flash_message
      flash[:notice] = "File updated."
      if %w{new editing}.include? @identifier.publication.status
        flash[:notice] += " Go to the <a href='#{url_for(@identifier.publication)}'>publication overview</a> if you would like to submit."
      end      
    end

    def save_comment (comment, commit_sha)
      if comment != nil && comment.strip != ""
        @comment = Comment.new( {:git_hash => commit_sha, :user_id => @current_user.id, :identifier_id => @identifier.id, :publication_id => @identifier.publication_id, :comment => comment, :reason => "commit" } )
        @comment.save
      end
    end

    def find_identifier
      @identifier = HGVMetaIdentifier.find(params[:id])
    end

end
