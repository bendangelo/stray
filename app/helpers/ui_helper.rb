module UiHelper
  def ui_menu_item(danger: false)
    danger ? "ui-menu-item ui-menu-item--danger" : "ui-menu-item"
  end

  def ui_dropdown_trigger(expand: false)
    base = "flex items-center justify-center rounded-md bg-transparent border-none cursor-pointer min-h-11 min-w-11 p-2 text-charcoal-300 hover:text-carrot-500 hover:bg-athens-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500 focus-visible:outline-offset-1"
    expand ? base + " w-full h-11" : base
  end

  def ui_button(variant: :primary, size: :md)
    size_class = { sm: "h-9 px-3 text-xs", md: "h-11 px-4 text-sm", lg: "h-12 px-6 text-base" }.fetch(size)
    variant_class = case variant
                    when :primary then "bg-carrot-500 hover:bg-carrot-600 text-white"
                    when :secondary then "bg-athens-400 hover:bg-athens-500 text-charcoal"
                    when :danger then "bg-athens-400 hover:bg-cerise/10 text-cerise"
                    else raise ArgumentError, "unknown ui_button variant: #{variant}"
                    end
    "inline-flex items-center justify-center gap-1.5 rounded-md border-3 border-charcoal font-bold cursor-pointer #{size_class} #{variant_class}"
  end

  def ui_input
    "w-full h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal placeholder:text-charcoal-300 focus:outline-none"
  end

  def ui_select
    "w-full h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none"
  end

  def ui_label
    "block text-sm font-bold text-charcoal mb-1"
  end

  def ui_card(padding: :default)
    padding_class = { default: "p-4", compact: "p-3", roomy: "p-8" }.fetch(padding)
    "border-3 border-charcoal rounded-md bg-athens-400 #{padding_class}"
  end

  def ui_page(tier: :form)
    { form: "max-w-3xl", list: "max-w-6xl", reader: "max-w-screen-xl" }.fetch(tier)
  end

  def ui_flash(kind)
    if kind == :alert
      "border-3 border-cerise text-cerise text-sm"
    else
      "border-3 border-mint-500 text-mint-700 text-sm"
    end
  end
end
