# encoding: utf-8
#
# Redmine - project management software
# Copyright (C) 2006-2017  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module IssuesHelper
  include ApplicationHelper
  include Redmine::Export::PDF::IssuesPdfHelper

  def issue_list(issues, &block)
    ancestors = []
    issues.each do |issue|
      while (ancestors.any? && !issue.is_descendant_of?(ancestors.last))
        ancestors.pop
      end
      yield issue, ancestors.size
      ancestors << issue unless issue.leaf?
    end
  end

  def grouped_issue_list(issues, query, &block)
    ancestors = []
    grouped_query_results(issues, query) do |issue, group_name, group_count, group_totals|
      while (ancestors.any? && !issue.is_descendant_of?(ancestors.last))
        ancestors.pop
      end
      yield issue, ancestors.size, group_name, group_count, group_totals
      ancestors << issue unless issue.leaf?
    end
  end

  # Renders a HTML/CSS tooltip
  #
  # To use, a trigger div is needed.  This is a div with the class of "tooltip"
  # that contains this method wrapped in a span with the class of "tip"
  #
  #    <div class="tooltip"><%= link_to_issue(issue) %>
  #      <span class="tip"><%= render_issue_tooltip(issue) %></span>
  #    </div>
  #
  def render_issue_tooltip(issue)
    @cached_label_status ||= l(:field_status)
    @cached_label_start_date ||= l(:field_start_date)
    @cached_label_due_date ||= l(:field_due_date)
    @cached_label_assigned_to ||= l(:field_assigned_to)
    @cached_label_priority ||= l(:field_priority)
    @cached_label_project ||= l(:field_project)

    link_to_issue(issue) + "<br /><br />".html_safe +
      "<strong>#{@cached_label_project}</strong>: #{link_to_project(issue.project)}<br />".html_safe +
      "<strong>#{@cached_label_status}</strong>: #{h(issue.status.name)}<br />".html_safe +
      "<strong>#{@cached_label_start_date}</strong>: #{format_date(issue.start_date)}<br />".html_safe +
      "<strong>#{@cached_label_due_date}</strong>: #{format_date(issue.due_date)}<br />".html_safe +
      "<strong>#{@cached_label_assigned_to}</strong>: #{h(issue.assigned_to)}<br />".html_safe +
      "<strong>#{@cached_label_priority}</strong>: #{h(issue.priority.name)}".html_safe
  end

  def issue_heading(issue)
    h("#{issue.tracker} ##{issue.id}")
  end

  def render_issue_subject_with_tree(issue)
    s = ''
    ancestors = issue.root? ? [] : issue.ancestors.visible.to_a
    ancestors.each do |ancestor|
      s << '<div>' + content_tag('p', link_to_issue(ancestor, :project => (issue.project_id != ancestor.project_id)))
    end
    s << '<div>'
    subject = h(issue.subject)
    if issue.is_private?
      subject = content_tag('span', l(:field_is_private), :class => 'private') + ' ' + subject
    end
    s << content_tag('h3', subject)
    s << '</div>' * (ancestors.size + 1)
    s.html_safe
  end

  def render_descendants_tree(issue)
    s = '<table class="list issues odd-even">'
    issue_list(issue.descendants.visible.preload(:status, :priority, :tracker, :assigned_to).sort_by(&:lft)) do |child, level|
      css = "issue issue-#{child.id} hascontextmenu #{child.css_classes}"
      css << " idnt idnt-#{level}" if level > 0
      s << content_tag('tr',
             content_tag('td', check_box_tag("ids[]", child.id, false, :id => nil), :class => 'checkbox') +
             content_tag('td', link_to_issue(child, :project => (issue.project_id != child.project_id)), :class => 'subject', :style => 'width: 50%') +
             content_tag('td', h(child.status), :class => 'status') +
             content_tag('td', link_to_user(child.assigned_to), :class => 'assigned_to') +
             content_tag('td', child.disabled_core_fields.include?('done_ratio') ? '' : progress_bar(child.done_ratio), :class=> 'done_ratio'),
             :class => css)
    end
    s << '</table>'
    s.html_safe
  end

  # Renders the list of related issues on the issue details view
  def render_issue_relations(issue, relations)
    manage_relations = User.current.allowed_to?(:manage_issue_relations, issue.project)

    s = ''.html_safe
    relations.each do |relation|
      other_issue = relation.other_issue(issue)
      css = "issue hascontextmenu #{other_issue.css_classes}"
      link = manage_relations ? link_to(l(:label_relation_delete),
                                  relation_path(relation),
                                  :remote => true,
                                  :method => :delete,
                                  :data => {:confirm => l(:text_are_you_sure)},
                                  :title => l(:label_relation_delete),
                                  :class => 'icon-only icon-link-break'
                                 ) : nil

      s << content_tag('tr',
             content_tag('td', check_box_tag("ids[]", other_issue.id, false, :id => nil), :class => 'checkbox') +
             content_tag('td', relation.to_s(@issue) {|other| link_to_issue(other, :project => Setting.cross_project_issue_relations?)}.html_safe, :class => 'subject', :style => 'width: 50%') +
             content_tag('td', other_issue.status, :class => 'status') +
             content_tag('td', other_issue.start_date, :class => 'start_date') +
             content_tag('td', other_issue.due_date, :class => 'due_date') +
             content_tag('td', other_issue.disabled_core_fields.include?('done_ratio') ? '' : progress_bar(other_issue.done_ratio), :class=> 'done_ratio') +
             content_tag('td', link, :class => 'buttons'),
             :id => "relation-#{relation.id}",
             :class => css)
    end

    content_tag('table', s, :class => 'list issues odd-even')
  end

  def issue_estimated_hours_details(issue)
    if issue.total_estimated_hours.present?
      if issue.total_estimated_hours == issue.estimated_hours
        l_hours_short(issue.estimated_hours)
      else
        s = issue.estimated_hours.present? ? l_hours_short(issue.estimated_hours) : ""
        s << " (#{l(:label_total)}: #{l_hours_short(issue.total_estimated_hours)})"
        s.html_safe
      end
    end
  end

  def issue_spent_hours_details(issue)
    if issue.total_spent_hours > 0
      path = project_time_entries_path(issue.project, :issue_id => "~#{issue.id}")

      if issue.total_spent_hours == issue.spent_hours
        link_to(l_hours_short(issue.spent_hours), path)
      else
        s = issue.spent_hours > 0 ? l_hours_short(issue.spent_hours) : ""
        s << " (#{l(:label_total)}: #{link_to l_hours_short(issue.total_spent_hours), path})"
        s.html_safe
      end
    end
  end

  # Returns an array of error messages for bulk edited issues
  def bulk_edit_error_messages(issues)
    messages = {}
    issues.each do |issue|
      issue.errors.full_messages.each do |message|
        messages[message] ||= []
        messages[message] << issue
      end
    end
    messages.map { |message, issues|
      "#{message}: " + issues.map {|i| "##{i.id}"}.join(', ')
    }
 end

  # Returns a link for adding a new subtask to the given issue
  def link_to_new_subtask(issue)
    attrs = {
      :parent_issue_id => issue
    }
    attrs[:tracker_id] = issue.tracker unless issue.tracker.disabled_core_fields.include?('parent_issue_id')
    link_to(l(:button_add), new_project_issue_path(issue.project, :issue => attrs, :back_url => issue_path(issue)))
  end

  def trackers_options_for_select(issue)
    trackers = issue.allowed_target_trackers
    if issue.new_record? && issue.parent_issue_id.present?
      trackers = trackers.reject do |tracker|
        issue.tracker_id != tracker.id && tracker.disabled_core_fields.include?('parent_issue_id')
      end
    end
    trackers.collect {|t| [t.name, t.id]}
  end

  class IssueFieldsRows
    include ActionView::Helpers::TagHelper

    def initialize
      @left = []
      @right = []
    end

    def left(*args)
      args.any? ? @left << cells(*args) : @left
    end

    def right(*args)
      args.any? ? @right << cells(*args) : @right
    end

    def size
      @left.size > @right.size ? @left.size : @right.size
    end

    def to_html
      content =
        content_tag('div', @left.reduce(&:+), :class => 'splitcontentleft') +
        content_tag('div', @right.reduce(&:+), :class => 'splitcontentleft')

      content_tag('div', content, :class => 'splitcontent')
    end

    def cells(label, text, options={})
      options[:class] = [options[:class] || "", 'attribute'].join(' ')
      content_tag 'div',
        content_tag('div', label + ":", :class => 'label') + content_tag('div', text, :class => 'value'),
        options
    end
  end

  def issue_fields_rows
    r = IssueFieldsRows.new
    yield r
    r.to_html
  end

  def render_half_width_custom_fields_rows(issue)
    values = issue.visible_custom_field_values.reject {|value| value.custom_field.full_width_layout?}
    return if values.empty?
    half = (values.size / 2.0).ceil
    issue_fields_rows do |rows|
      values.each_with_index do |value, i|
        css = "cf_#{value.custom_field.id}"
        m = (i < half ? :left : :right)
        rows.send m, custom_field_name_tag(value.custom_field), show_value(value), :class => css
      end
    end
  end

  def render_full_width_custom_fields_rows(issue)
    values = issue.visible_custom_field_values.select {|value| value.custom_field.full_width_layout?}
    return if values.empty?

    s = ''.html_safe
    values.each_with_index do |value, i|
      attr_value = show_value(value)
      next if attr_value.blank?

      if value.custom_field.text_formatting == 'full'
        attr_value = content_tag('div', attr_value, class: 'wiki')
      end

      content =
          content_tag('hr') +
          content_tag('p', content_tag('strong', custom_field_name_tag(value.custom_field) )) +
          content_tag('div', attr_value, class: 'value')
      s << content_tag('div', content, class: "cf_#{value.custom_field.id} attribute")
    end
    s
  end

  # Returns the path for updating the issue form
  # with project as the current project
  def update_issue_form_path(project, issue)
    options = {:format => 'js'}
    if issue.new_record?
      if project
        new_project_issue_path(project, options)
      else
        new_issue_path(options)
      end
    else
      edit_issue_path(issue, options)
    end
  end

  # Returns the number of descendants for an array of issues
  def issues_descendant_count(issues)
    ids = issues.reject(&:leaf?).map {|issue| issue.descendants.ids}.flatten.uniq
    ids -= issues.map(&:id)
    ids.size
  end

  def issues_destroy_confirmation_message(issues)
    issues = [issues] unless issues.is_a?(Array)
    message = l(:text_issues_destroy_confirmation)

    descendant_count = issues_descendant_count(issues)
    if descendant_count > 0
      message << "\n" + l(:text_issues_destroy_descendants_confirmation, :count => descendant_count)
    end
    message
  end

  # Returns an array of users that are proposed as watchers
  # on the new issue form
  def users_for_new_issue_watchers(issue)
    users = issue.watcher_users.select{|u| u.status == User::STATUS_ACTIVE}
    if issue.project.users.count <= 20
      users = (users + issue.project.users.sort).uniq
    end
    users
  end

  def email_issue_attributes(issue, user, html)
    items = []
    %w(author status priority assigned_to category fixed_version).each do |attribute|
      unless issue.disabled_core_fields.include?(attribute+"_id")
        if html
          items << content_tag('strong', "#{l("field_#{attribute}")}: ") + (issue.send attribute)
        else
          items << "#{l("field_#{attribute}")}: #{issue.send attribute}"
        end
      end
    end
    issue.visible_custom_field_values(user).each do |value|
      if html
        items << content_tag('strong', "#{value.custom_field.name}: ") + show_value(value, false)
      else
        items << "#{value.custom_field.name}: #{show_value(value, false)}"
      end
    end
    items
  end

  def render_email_issue_attributes(issue, user, html=false)
    items = email_issue_attributes(issue, user, html)
    if html
      content_tag('ul', items.map{|s| content_tag('li', s)}.join("\n").html_safe, :class => "details")
    else
      items.map{|s| "* #{s}"}.join("\n")
    end
  end

  # Returns the textual representation of a journal details
  # as an array of strings
  def details_to_strings(details, no_html=false, options={})
    options[:only_path] = (options[:only_path] == false ? false : true)
    strings = []
    values_by_field = {}
    details.each do |detail|
      if detail.property == 'cf'
        field = detail.custom_field
        if field && field.multiple?
          values_by_field[field] ||= {:added => [], :deleted => []}
          if detail.old_value
            values_by_field[field][:deleted] << detail.old_value
          end
          if detail.value
            values_by_field[field][:added] << detail.value
          end
          next
        end
      end
      strings << show_detail(detail, no_html, options)
    end
    if values_by_field.present?
      multiple_values_detail = Struct.new(:property, :prop_key, :custom_field, :old_value, :value)
      values_by_field.each do |field, changes|
        if changes[:added].any?
          detail = multiple_values_detail.new('cf', field.id.to_s, field)
          detail.value = changes[:added]
          strings << show_detail(detail, no_html, options)
        end
        if changes[:deleted].any?
          detail = multiple_values_detail.new('cf', field.id.to_s, field)
          detail.old_value = changes[:deleted]
          strings << show_detail(detail, no_html, options)
        end
      end
    end
    strings
  end

  # Returns the textual representation of a single journal detail
  def show_detail(detail, no_html=false, options={})
    multiple = false
    show_diff = false
    no_details = false

    case detail.property
    when 'attr'
      field = detail.prop_key.to_s.gsub(/\_id$/, "")
      label = l(("field_" + field).to_sym)
      case detail.prop_key
      when 'due_date', 'start_date'
        value = format_date(detail.value.to_date) if detail.value
        old_value = format_date(detail.old_value.to_date) if detail.old_value

      when 'project_id', 'status_id', 'tracker_id', 'assigned_to_id',
            'priority_id', 'category_id', 'fixed_version_id'
        value = find_name_by_reflection(field, detail.value)
        old_value = find_name_by_reflection(field, detail.old_value)

      when 'estimated_hours'
        value = l_hours_short(detail.value.to_f) unless detail.value.blank?
        old_value = l_hours_short(detail.old_value.to_f) unless detail.old_value.blank?

      when 'parent_id'
        label = l(:field_parent_issue)
        value = "##{detail.value}" unless detail.value.blank?
        old_value = "##{detail.old_value}" unless detail.old_value.blank?

      when 'is_private'
        value = l(detail.value == "0" ? :general_text_No : :general_text_Yes) unless detail.value.blank?
        old_value = l(detail.old_value == "0" ? :general_text_No : :general_text_Yes) unless detail.old_value.blank?

      when 'description'
        show_diff = true
      end
    when 'cf'
      custom_field = detail.custom_field
      if custom_field
        label = custom_field.name
        if custom_field.format.class.change_no_details
          no_details = true
        elsif custom_field.format.class.change_as_diff
          show_diff = true
        else
          multiple = custom_field.multiple?
          value = format_value(detail.value, custom_field) if detail.value
          old_value = format_value(detail.old_value, custom_field) if detail.old_value
        end
      end
    when 'attachment'
      label = l(:label_attachment)
    when 'relation'
      if detail.value && !detail.old_value
        rel_issue = Issue.visible.find_by_id(detail.value)
        value = rel_issue.nil? ? "#{l(:label_issue)} ##{detail.value}" :
                  (no_html ? rel_issue : link_to_issue(rel_issue, :only_path => options[:only_path]))
      elsif detail.old_value && !detail.value
        rel_issue = Issue.visible.find_by_id(detail.old_value)
        old_value = rel_issue.nil? ? "#{l(:label_issue)} ##{detail.old_value}" :
                          (no_html ? rel_issue : link_to_issue(rel_issue, :only_path => options[:only_path]))
      end
      relation_type = IssueRelation::TYPES[detail.prop_key]
      label = l(relation_type[:name]) if relation_type
    end
    call_hook(:helper_issues_show_detail_after_setting,
              {:detail => detail, :label => label, :value => value, :old_value => old_value })

    label ||= detail.prop_key
    value ||= detail.value
    old_value ||= detail.old_value

    unless no_html
      label = content_tag('strong', label)
      old_value = content_tag("i", h(old_value)) if detail.old_value
      if detail.old_value && detail.value.blank? && detail.property != 'relation'
        old_value = content_tag("del", old_value)
      end
      if detail.property == 'attachment' && value.present? &&
          atta = detail.journal.journalized.attachments.detect {|a| a.id == detail.prop_key.to_i}
        # Link to the attachment if it has not been removed
        value = link_to_attachment(atta, only_path: options[:only_path])
        if options[:only_path] != false
          value += ' '
          value += link_to_attachment atta, class: 'icon-only icon-download', title: l(:button_download), download: true
        end
      else
        value = content_tag("i", h(value)) if value
      end
    end

    if no_details
      s = l(:text_journal_changed_no_detail, :label => label).html_safe
    elsif show_diff
      s = l(:text_journal_changed_no_detail, :label => label)
      unless no_html
        diff_link = link_to 'diff',
          diff_journal_url(detail.journal_id, :detail_id => detail.id, :only_path => options[:only_path]),
          :title => l(:label_view_diff)
        s << " (#{ diff_link })"
      end
      s.html_safe
    elsif detail.value.present?
      case detail.property
      when 'attr', 'cf'
        if detail.old_value.present?
          l(:text_journal_changed, :label => label, :old => old_value, :new => value).html_safe
        elsif multiple
          l(:text_journal_added, :label => label, :value => value).html_safe
        else
          l(:text_journal_set_to, :label => label, :value => value).html_safe
        end
      when 'attachment', 'relation'
        l(:text_journal_added, :label => label, :value => value).html_safe
      end
    else
      l(:text_journal_deleted, :label => label, :old => old_value).html_safe
    end
  end

  # Find the name of an associated record stored in the field attribute
  def find_name_by_reflection(field, id)
    unless id.present?
      return nil
    end
    @detail_value_name_by_reflection ||= Hash.new do |hash, key|
      association = Issue.reflect_on_association(key.first.to_sym)
      name = nil
      if association
        record = association.klass.find_by_id(key.last)
        if record
          name = record.name.force_encoding('UTF-8')
        end
      end
      hash[key] = name
    end
    @detail_value_name_by_reflection[[field, id]]
  end

  # Renders issue children recursively
  def render_api_issue_children(issue, api)
    return if issue.leaf?
    api.array :children do
      issue.children.each do |child|
        api.issue(:id => child.id) do
          api.tracker(:id => child.tracker_id, :name => child.tracker.name) unless child.tracker.nil?
          api.subject child.subject
          render_api_issue_children(child, api)
        end
      end
    end
  end
end
