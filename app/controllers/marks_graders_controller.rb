# Manages actions relating to assigning graders.
class MarksGradersController < ApplicationController
  include MarksGradersHelper

  before_filter :authorize_only_for_admin

  def populate
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    @students = students_with_assoc
    @table_rows = construct_table_rows(@students, @grade_entry_form)
  end

  def populate_graders
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    @graders = Ta.all
    @table_rows = construct_grader_table_rows(@graders, @grade_entry_form)
  end

  def index
    @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
  end

  # Assign TAs to Students via a csv file
  def csv_upload_grader_groups_mapping
    if !request.post? || params[:grader_mapping].nil?
      flash[:error] = I18n.t('csv.student_to_grader')
      redirect_to action: 'index', grade_entry_form_id: params[:grade_entry_form_id]
      return
    end

    invalid_lines = GradeEntryStudent.assign_tas_by_csv(params[:grader_mapping].read,
      params[:grade_entry_form_id], params[:encoding])

    if invalid_lines.size > 0
      flash[:error] = I18n.t('graders.lines_not_processed') + invalid_lines.join(', ')
    end

    redirect_to action: 'index', grade_entry_form_id: params[:grade_entry_form_id]
  end

  #Download grader/student mappings in CSV format.
  def download_grader_students_mapping
    grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
    students = students_with_assoc

    file_out = CSV.generate do |csv|
      students.each do |student|
        # csv format is student_name, ta1_name, ta2_name, ... etc
        student_array = [student.user_name]
        grade_entry_student = student.grade_entry_students.find do |entry|
          entry.grade_entry_form_id == grade_entry_form.id
        end
        unless grade_entry_student.nil?
          grade_entry_student.tas.each { |ta| student_array.push(ta.user_name) }
        end

        csv << student_array
      end
    end

    send_data(file_out, type: 'text/csv', disposition: 'inline')
  end

  # These actions act on all currently selected graders & students
  def global_actions
    student_ids = params[:students]
    grader_ids = params[:graders]

    case params[:current_table]
      when 'groups_table'
        @grade_entry_form = GradeEntryForm.find(params[:grade_entry_form_id])
        if params[:students].nil? or params[:students].size ==  0
         # If there is a global action than there should be a student selected
          if params[:global_actions]
            @global_action_warning = t('assignment.group.select_a_student')
            render partial: 'shared/global_action_warning', formats:[:js], handlers: [:erb]
            return
          end
        end
        students = Student.where(id: student_ids)

        case params[:global_actions]
          when "assign"
            if params[:graders].nil? or params[:graders].size ==  0
              @global_action_warning = t('assignment.group.select_a_grader')
              render partial: 'shared/global_action_warning', formats:[:js], handlers: [:erb]
              return
            end
            assign_all_graders(student_ids, grader_ids, @grade_entry_form)
            return
          when "unassign"
            remove_graders(students, params)
            return
          when "random_assign"
            if params[:graders].nil? or params[:graders].size ==  0
              @global_action_warning = t('assignment.group.select_a_grader')
              render partial: 'shared/global_action_warning', formats:[:js], handlers: [:erb]
              return
            end
            randomly_assign_graders(student_ids, grader_ids, @grade_entry_form)
            return
        end
    end
  end

  private

  def students_with_assoc
    Student.includes(:section, grade_entry_students: :tas)
  end

  def randomly_assign_graders(student_ids, grader_ids, form)
    GradeEntryStudent.randomly_assign_tas(student_ids, grader_ids, form)
    render nothing: true
  end

  def assign_all_graders(student_ids, grader_ids, form)
    GradeEntryStudent.assign_all_tas(student_ids, grader_ids, form)
    render nothing: true
  end

  # Removes the graders contained in params from the students given in students.
  # This is meant to be called with the params from global_actions, and for
  # each grader to delete it will have a parameter
  # of the form "studentid_graderid"
  def remove_graders(students, params)
    students.each do |student|
      grader_params = params.find_all{|p| p[0].include?("#{student.id}_")}
      grade_entry_student = @grade_entry_form.grade_entry_students.find_by_user_id(student.id)
      if grader_params != [] and !grade_entry_student.nil?
        members = grade_entry_student.tas.delete_if do |grader|
          !params["#{student.id}_#{grader.user_name}"]
        end
        grade_entry_student.remove_tas(members.map{ |member| member.id })
      end
    end

    construct_all_rows(students, Ta.all)
    render :modify_groupings
  end

  def construct_all_rows(students, graders)
    @students_data = construct_table_rows(students, @grade_entry_form)
    @graders_data = construct_grader_table_rows(graders, @grade_entry_form)
  end
end
