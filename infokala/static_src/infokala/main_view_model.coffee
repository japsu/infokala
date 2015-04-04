Promise = require 'bluebird'
ko = require 'knockout'
_ = require 'lodash'

{getAllMessages, getMessagesSince, getConfig, sendMessage} = require './message_service.coffee'

refreshMilliseconds = 5 * 1000

module.exports = class MainViewModel
  constructor: ->
    @messages = ko.observableArray []
    @latestMessageTimestamp = null
    @user = ko.observable
      displayName: ""
      username: ""

    @author = ko.observable ""
    @message = ko.observable ""
    @manualMessageType = ko.observable ""
    @messageTypes = ko.observable []
    @messageTypeFilters = ko.observable []
    @activeFilter = ko.observable slug: null

    # XXX O(n) on every new or changed message - bad
    @visibleMessages = ko.pureComputed =>
      activeFilter = @activeFilter()

      if activeFilter?.slug
        _.filter @messages(), (message) -> message.messageType.slug == activeFilter.slug
      else
        @messages()

    @effectiveMessageType = ko.pureComputed =>
      activeFilter = @activeFilter()

      if activeFilter?.slug
        activeFilter.slug
      else
        @manualMessageType()

    @messageTypesBySlug = ko.pureComputed => _.indexBy @messageTypes(), 'slug'

    # Using ko.pureComputed would be O(n) on every new or changed message – suicide
    @messagesById = {}
    @messages.subscribe @messageUpdated, null, 'arrayChange'

    Promise.all([getConfig(), getAllMessages()]).spread (config, messages) =>
      @user config.user
      @author config.user.displayName

      @messageTypes config.messageTypes
      @messageTypeFilters [
        name: 'Kaikki'
        slug: null
      ].concat config.messageTypes
      @manualMessageType config.defaultMessageType

      @updateMessages messages
      @setupPolling()

  updateMessages: (updatedMessages) =>
    updatedMessages.forEach (updatedMessage) =>
      existingMessage = @messagesById[updatedMessage.id]

      if existingMessage
        updatedMessage.index = existingMessage.index
        @messages.splice existingMessage.index, 1, updatedMessage
      else
        @messages.push updatedMessage

        if !@latestMessageTimestamp or updatedMessage.createdAt > @latestMessageTimestamp
          @latestMessageTimestamp = updatedMessage.createdAt

        window.scrollTo 0, document.body.scrollHeight

  messageUpdated: (changes) =>
    console?.log 'messageUpdated', changes
    changes.forEach (change) =>
      return unless change.status == 'added'

      message = change.value
      @messagesById[message.id] = message

  setupPolling: =>
    window.setInterval @refresh, refreshMilliseconds

  refresh: =>
    getMessagesSince(@latestMessageTimestamp).then @newMessages

  sendMessage: (formElement) =>
    return if @message() == ""
    sendMessage(
      messageType: @effectiveMessageType()
      author: @author()
      message: @message()
    ).then (newMessage) =>
      @message ""
      @updateMessages [newMessage]

  cycleMessageState: (message) ->
    updateMessage(
      state: @nextState(message.state)
    ).then (updatedMessage) =>
      @updateMessages [updatedMessage]

  shouldShowMessageType: => !@activeFilter().slug
