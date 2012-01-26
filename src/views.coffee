### The view that manages displaying the list of suggestions ###
class SuggestionView extends Backbone.View
  ### Private fields ###
  _forceClosed: false
  _menuVisible: false
  _controller: null
  _menu: null
  _previousValue: null
  _blurTimeout = null
  _donotBlur = false
  
  ### Templates that define the layout of the menu for each of it's states ###
  templates:
    container: _.template('<div class="<%= cssClass %>"></div>')
    default: _.template('<span class="message default">Begin typing for suggestions</span>')
    loading: _.template('<span class="message loading">Begin typing for suggestions (Loading...)</span>')
    loadedList: _.template('<ol class="<%= cssClass %>"></ol><ol class="<%= pagingPanelCssClass %>"><li><a href="javascript:void(0)" class="<%= prevActionCssClass %>">Prev</a></li><li><a href="javascript:void(0)" class="<%= nextActionCssClass %>">Next</a></li></ol>')
    loadedItem: _.template('<li class="<%= cssClass %>"><a href="javascript:void(0)" class="<%= actionCssClass %>"><%= value %></a></li>')
    empty: _.template('<span class="message empty">No suggestions were found</span>')
    error: _.template('<span class="message error">An error has occurred while retrieving data</span>')
      
  ### Event callbacks ###
  callbacks:
    selected: null
    abort: null
    keyDown: null
    keyUp: null
    show: null
    hide: null
  
  ### Default options ###
  options:
    zIndex: 500
    cssClass: 'suggestions-menu'
    pagingPanelCssClass: 'suggestions-paging-panel'
    nextActionCssClass: 'suggestions-next-action'
    prevActionCssClass: 'suggestions-prev-action'
    loadedListCssClass: 'suggestions-loaded-list'
    listItemCssClass: 'suggestions-list-item'
    listItemActionCssClass: 'suggestions-list-item-action'
    selectedCssClass: 'selected'
    enableForceClose: true
    templates: null
    callbacks: null
    valueField: 'value'
    paging: true
  
  _onkeydown: (event) => @_keydown event
  _onkeyup: (event) => @_keyup event
  _onfocus: (event) => @_focus event
  _onblur: (event) => @_blur event
    
  ### Initializes the object ###
  initialize: ->
    @el.attr 'autocomplete', 'off'
    @templates = _.clone _.defaults(@options.templates, @templates) if @options?.templates?
    @callbacks = _.clone _.defaults(@options.callbacks, @callbacks) if @options?.callbacks?
    
    @options.callbacks =
      initiateSuggestion: => @_initiateSuggestion()
      checkingLengthThreshold: (does_meet) => @_checkingLengthThreshold(does_meet)
      suggesting: => @_suggesting()
      suggested: (cached, pagingVector) => @_suggested(cached, pagingVector)
      error: (jqXHR, textStatus, errorThrown) => @_error(jqXHR, textStatus, errorThrown)
      loading: (pagingVector) => @_loading(pagingVector)
      enabled: => @_enabled()
      disabled: => @_disabled()

    @_controller = new SuggestionController this, @el, @options
    
    @_generateMenu()
      
  is_enabled: ->
    @_controller.is_enabled()
    
  _enabled: ->
    @el.bind (if $.browser.opera then 'keypress' else 'keydown'), @_onkeydown
    @el.bind
      keyup: @_onkeyup
      blur: @_onblur
      focus: @_onfocus
      
    @callbacks?.enabled?.call(this)
    
  _disabled: ->
    @el.blur()
    
    @el.unbind (if $.browser.opera then 'keypress' else 'keydown'), @_onkeydown
    @el.unbind
      keyup: @_onkeyup
      blur: @_onblur
      focus: @_onfocus
      
    @callbacks?.disabled?.call(this)
    
  enable: ->
    @_controller.enable()
        
  disable: ->
    @_controller.disable()

  ### Callback for when the controller is checking the length threshold prior
      to making a suggestion ###
  _checkingLengthThreshold: (does_meet) ->
    @callbacks.checkingLengthThreshold?.call(this, does_meet)
    @render 'default' unless does_meet
    
  ### Callback for when a suggestion is initialized ###
  _initiateSuggestion: ->
    @callbacks.initiateSuggestion?.call(this)
    @render 'default' unless @el.val()?.length > 0

  ### Callback for when a suggestion is processing ###
  _suggesting: ->
    @callbacks.suggesting?.call(this)

  _loading: (pagingVector) ->
    @callbacks.loading?.call(this, pagingVector)
    @render 'loading', { pagingVector, pagingVector }
        
  ### Callback for when a suggestions is completed ###
  _suggested: (cached, pagingVector) ->
    @callbacks.suggested?.call(this, cached)
    suggestions = cached.get('suggestions')
    if suggestions.length > 0 then @render 'loaded', { cached: cached, pagingVector: pagingVector } else @render 'empty'
    
  ### Callback for when there is an AJAX error durion a suggestion ###
  _error: (jqXHR, textStatus, errorThrown) ->
    if (textStatus != 'abort')
      @callbacks.error?.call(this, jqXHR, textStatus, errorThrown)
      @render 'error'
    else
      @callbacks.abort?.call(this, jqXHR, textStatus, errorThrown)
      @render 'default'
    
  ### Manages user input ###
  _keydown: (event) ->
    return if @_forceClosed
    
    return if @callbacks.keyDown?.call(this, event) == true
    
    switch event.keyCode
      when KEYS.UP
        return unless @_menuVisible
        event.preventDefault()
        
        selected = @filterFind @_menu, ".#{@options.listItemCssClass}.#{@options.selectedCssClass}"

        if selected?.size() > 0 and selected?.prev().length > 0
          selected.removeClass @options.selectedCssClass
          selected.prev().addClass @options.selectedCssClass

      when KEYS.DOWN            
        return unless @_menuVisible
        event.preventDefault()
        
        selected = @filterFind @_menu, ".#{@options.listItemCssClass}.#{@options.selectedCssClass}"
        
        if selected?.size() > 0 and selected?.next().length > 0
          selected.removeClass @options.selectedCssClass
          selected.next().addClass @options.selectedCssClass

      when KEYS.ENTER
        return unless @_menuVisible
        event.preventDefault()
        
        selected = @filterFind @_menu, ".#{@options.listItemCssClass}.#{@options.selectedCssClass} a"

        if selected?.get(0)?
          selected.click()
          @hide()

      when KEYS.ESC
        return unless @_menuVisible && @options.enableForceClose == true
        event.preventDefault()
        
        @_forceClosed = true
        @hide()
    
  ### Manages user input and potentially initiates a suggestion call ###
  _keyup: (event) ->
    return if @_forceClosed
    
    return if @callbacks.keyUp?.call(this, event) == true
        
    switch event.keyCode
      when KEYS.UP, KEYS.DOWN, KEYS.ENTER, KEYS.ESC
        if @_menuVisible then event.preventDefault()
      else
        if @_menuVisible and @_previousValue isnt @el.val()
          @_controller.suggest()
          @_previousValue = @el.val()

  ### Shows the menu when the element's focus event is fired ###
  _focus: (event) ->
    @_forceClosed = false

    return if @_menuVisible
    @show()
    @_controller.suggest()
    
  
  ### Hides the menu when the element's blur event is fired ###
  _blur: (event) ->
    unless @_donotBlur
      callback = => @hide()
      @_blurTimeout = setTimeout callback, 200
    
  ### Generates the menu HTML ###
  _generateMenu: ->
    @_menu = $(@templates.container({ cssClass: @options.cssClass })).css
      display: 'none'

    @el.parent().append(@_menu)
    
  ### Displays the menu ###
  show: ->
    return if @_menuVisible
    
    @callbacks.show?.call(this)
    clearTimeout @_blurTimeout
    @_menuVisible = true
    @_controller.halt()
    @render 'default'

    @_menu.fadeIn
      duration: 200
      
  ### Hides the menu ###
  hide: ->
    return unless @_menuVisible

    @callbacks.hide?.call(this)
    @_previousValue = null
    @_menuVisible = false
    @_controller.halt()
    @_menu.fadeOut
      duration: 200
      
  ### Passes halt to the _controller property ###
  halt: ->
    @_controller.halt();
      
  ### Selects a value ###
  select: (val) ->
    @el.val val[@options.valueField]
    @callbacks.selected?.call(this, val)
    
  filterFind: (jq, selector) ->
    obj = jq.filter(selector)
    obj = jq.find(selector) unless obj.size() > 0
    
    obj
  
  _moreClick: (vector) =>
    nextAction = @filterFind(@_menu, ".#{@options.nextActionCssClass}")
    prevAction = @filterFind(@_menu, ".#{@options.prevActionCssClass}")
    prevAction.unbind 'click', @_prevClick
    nextAction.unbind 'click', @_nextClick
    prevAction.bind 'click', @_moreLoadingClick
    nextAction.bind 'click', @_moreLoadingClick
    @filterFind(@_menu, ".#{@options.listItemActionCssClass}").unbind 'click', @_listItemClick
    @filterFind(@_menu, ".#{@options.listItemActionCssClass}").bind 'click', @_listItemLoadingClick
    
    @_donotBlur = true
    clearTimeout @_blurTimeout
    event.preventDefault()
  
    @el.focus()
    @_donotBlur = false
    @_controller.suggest(vector)
    
  _moreLoadingClick: (event) =>    
    @_donotBlur = true
    clearTimeout @_blurTimeout
    event.preventDefault()
  
    @el.focus()
    @_donotBlur = false
    
  _nextClick: (event) =>
      @_moreClick PAGING_VECTOR.NEXT
      
  _prevClick: (event) =>
      @_moreClick PAGING_VECTOR.PREV
    
  _loadingClick: (event) ->
      event.preventDefault()
      
  _listItemClick: (event) =>
      event.preventDefault()
      @select $(event.currentTarget).data('suggestion')
      
  ### Renders the template of the menu ###
  render: (state, parameters) ->    
    switch state
      when 'default'
        @_menu.empty()
        @_menu.append @templates.default()
      when 'loading'
        if parameters? && (parameters.pagingVector == PAGING_VECTOR.NEXT || parameters.pagingVector == PAGING_VECTOR.PREV)

        else
          @_menu.empty()
          @_menu.append @templates.loading()
      when 'loaded'
        if parameters? && (parameters.pagingVector == PAGING_VECTOR.NEXT || parameters.pagingVector == PAGING_VECTOR.PREV)
          container = @filterFind(@_menu, ".#{@options.loadedListCssClass}")
          
          suggestions = parameters.cached.get('suggestions')
          container.empty();
          for suggestion in suggestions
            suggestion.cssClass = @options.listItemCssClass
            suggestion.actionCssClass = @options.listItemActionCssClass
        
            li = $(@templates.loadedItem(suggestion))
            @filterFind(li, ".#{@options.listItemActionCssClass}").data('suggestion', suggestion)
            container.append(li)
            
          nextAction = @filterFind(@_menu, ".#{@options.nextActionCssClass}")
          prevAction = @filterFind(@_menu, ".#{@options.prevActionCssClass}")
          
          actionsRemoved = 0

          prevAction.unbind 'click', @_moreLoadingClick
          nextAction.unbind 'click', @_moreLoadingClick
          prevAction.bind 'click', @_prevClick
          nextAction.bind 'click', @_nextClick
          
          unless @_controller.get_current_page() > 1
            prevAction.css 'display', 'none'
            actionsRemoved++
          else
            prevAction.css 'display', 'block'

          unless parameters.cached.get('hasMore') == true
            nextAction.css 'display', 'none'
            actionsRemoved++
          else
            nextAction.css 'display', 'block'
          
          if actionsRemoved == 2 or @options.paging == false
            @filterFind(@_menu, ".#{@options.pagingPanelCssClass}").css('display', 'none')
          else
            @filterFind(@_menu, ".#{@options.pagingPanelCssClass}").css('display', 'block')
            
          @filterFind(@_menu, ".#{@options.listItemCssClass}:first-child").addClass('selected')
        
          
          @filterFind(@_menu, ".#{@options.listItemActionCssClass}").unbind 'click', @_listItemLoadingClick
          @filterFind(@_menu, ".#{@options.listItemActionCssClass}").bind 'click', @_listItemClick
        else
          @_menu.empty()
          list = $(@templates.loadedList(
            cssClass: @options.loadedListCssClass
            pagingPanelCssClass: @options.pagingPanelCssClass
            prevActionCssClass: @options.prevActionCssClass
            nextActionCssClass: @options.nextActionCssClass));

          container = @filterFind(list, ".#{@options.loadedListCssClass}")

          suggestions = parameters.cached.get('suggestions')
          for suggestion in suggestions
            suggestion.cssClass = @options.listItemCssClass
            suggestion.actionCssClass = @options.listItemActionCssClass
        
            li = $(@templates.loadedItem(suggestion))
            @filterFind(li, ".#{@options.listItemActionCssClass}").data('suggestion', suggestion)            
            container.append(li)
      
          @_menu.append list
      
          nextAction = @filterFind(list, ".#{@options.nextActionCssClass}")
          prevAction = @filterFind(list, ".#{@options.prevActionCssClass}")

          prevAction.unbind 'click', @_moreLoadingClick
          nextAction.unbind 'click', @_moreLoadingClick
          prevAction.bind 'click', @_prevClick
          nextAction.bind 'click', @_nextClick
            
          actionsRemoved = 0

          unless @_controller.get_current_page() > 1
            prevAction.css 'display', 'none'
            actionsRemoved++

          unless parameters.cached.get('hasMore') == true
            nextAction.css 'display', 'none'
            actionsRemoved++
          
          @filterFind(list, ".#{@options.pagingPanelCssClass}").css('display', 'none') if actionsRemoved == 2 or @options.paging == false
       
      
          @filterFind(list, ".#{@options.listItemCssClass}:first-child").addClass('selected')
          
          @filterFind(@_menu, ".#{@options.listItemActionCssClass}").unbind 'click', @_listItemLoadingClick
          @filterFind(@_menu, ".#{@options.listItemActionCssClass}").bind 'click', @_listItemClick
          
      when 'empty'
        @_menu.empty()
        @_menu.append @templates.empty()
      when 'error' 
        @_menu.empty()
        @_menu.append @templates.error()
      else @render 'default'