#encoding: utf-8
class Application
  def available_dates(site)
    limit = (current_user.in_role? :hq) ? 7 : 2
    repository(:default).adapter.select(
      "select date from site_reports, sites where sites.name='#{site}' and sites.id=site_reports.site_id order by date desc limit #{limit}")
  end

  get '/site/:site_id/?:date?', :auth => [:hq, :auditor, :operator] do
    @date = params[:date] || Date.today
    @site_report = case params[:date].nil?
                   when false
                     @site_report = SiteReport.first(:site_id => params[:site_id], :date => params[:date])
                   else
                     @site_report = SiteReport.first(:site_id => params[:site_id], :order => [:date.desc], :limit => 1)
                   end
    @site_name = @site_report.site.name 
    @date = @site_report.date.to_s
    @available_dates = available_dates(@site_name)
    @status_text = case @site_report.status
                   when 0 then '未輸入'
                   when 1 then '未核覆'
                   when 2 then '已核覆'
                   end
    @has_bc = true if current_user.in_role? :hq
    # not editable when status is 0 and user is auditor 
    @editable = @site_report.status != 0 || !current_user.in_role?(:auditor) || current_user.deputy
    show :site_report
  end

  post '/site/:site_id/:date', :auth => [:hq, :auditor, :operator] do
    log = {}
    @date = params[:date]
    @site_report = SiteReport.first(:site_id => params[:site_id], :date => @date)
    @site_name = @site_report.site.name
    @available_dates = available_dates(@site_name)
    @errors, state_changed = authorize_update(current_user, @site_report, log)
    @errors.merge! validate(params["site_report"])
    if @errors.size > 0
      flash[:error] = @errors[:authorize] 
      @status_text = params[:status]
      # @site_report = OpenStruct.new params[:site_report]
      redirect "/site/" + params[:site_id] + "/" + params[:date]
    else
      [:total_trips, :operator_tests, :trainees, :pumpings, :repeats].each do |k|
        ov = @site_report.send(k)
        nv = params["site_report"][k.to_s].to_i
        if ov != nv
          log[:changes] = [] if !log[:changes]
          log[:changes] << {:f => k.to_s, :ov => ov, :nv => nv}
          @site_report.send("#{k.to_s}=", nv)
        end
      end
      if @site_report.comment != params["site_report"]["comment"]
        log[:changes] = [] if !log[:changes]
        log[:changes] << {:f => 'comment', :ov => @site_report.comment, :nv => params["site_report"]["comment"]}
        @site_report.comment = params["site_report"]["comment"]
      end
      if log[:changes] || state_changed
        @site_report.save
        if log[:changes] || log[:message]
          log[:owner] = current_user.id
          srl = SiteReportLog.new(:log => JSON.generate(log))
          srl.site_report = @site_report
          srl.save
        end
      end
      @status_text = case @site_report.status
                     when 0 then '未輸入'
                     when 1 then '未核覆'
                     when 2 then '已核覆'
                     end
    end
    @has_bc = true if current_user.in_role? :hq
    show :site_report
  end

  def authorize_update(current_user, report, log)
    state_changed = false
    errors = {}
    case report.status
    when 0 # 未輸入
      report.inputter = current_user
      #report.auditor = current_user unless current_user.in_role? :operator
      state_changed = true
    when 1 # 未核覆
      #if !current_user.in_role? :operator
      if current_user != report.inputter
        report.auditor = current_user
        state_changed = true
        log[:message] = "核覆資料"
      end
    when 2 # 已核覆
      if current_user.in_role? :operator
        errors[:authorize] = "無法更改已核覆報告"
      end
    end
    [errors, state_changed]
  end

  def validate(params)
    errors = {}
    errors[:operator_tests] = "調度測試 必須是整數" unless is_integer(params["operator_tests"])
    errors[:trainees] = "見習 必須是整數" unless is_integer(params["trainees"])
    errors[:pumpings] = "抽班 必須是整數" unless is_integer(params["pumpings"])
    errors[:repeats] = "重覆 必須是整數" unless is_integer(params["repeats"])
    errors
  end
  
  def is_integer(s)
     !!(s.strip =~ /^[0-9]+$/)
  end
end
