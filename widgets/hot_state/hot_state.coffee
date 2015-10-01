class Dashing.HotState extends Dashing.Widget

  constructor: ->
    super

  onData: (data) ->
    return if not @state
    state = @state.toLowerCase()

    if [ 'critical', 'warning', 'ok', 'unknown' ].indexOf(state) != -1
      backgroundClass = "hot-state-#{state}"
    else
      backgroundClass = "hot-state-neutral"

    lastClass = @lastClass

    if lastClass != backgroundClass
      $(@node).toggleClass("#{lastClass} #{backgroundClass}")
      @lastClass = backgroundClass

      audiosound = @get(state + 'sound')
      audioplayer = new Audio(audiosound) if audiosound?
      if audioplayer
        audioplayer.play()

  ready: ->
    @onData(null)
