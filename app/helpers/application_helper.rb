module ApplicationHelper
  FORMAT_LABELS = { "commander" => "Commander", "standard" => "Standard" }.freeze

  def format_label(format) = FORMAT_LABELS.fetch(format.to_s, format.to_s.capitalize)

  def table_title(table) = table.name.presence || "Mesa #{table.slug}"
end
