module tvitch

// the tvitch module aids in creating your own twitch chat bot!
// the backend code is a bit messy, but it sure works.
//
// ```
// import tvitch
//
// fn main() {
// 	mut client := tvitch.new_client('yourauthtokenhere', ['#channel1', '#channel2'], 'yourbotusername')
// 	client.on_message(fn [mut c] (channel string, b tvitch.TwitchMessage) {
// 		if !b.content.starts_with('!') { return }
//
// 		match b.content[1..] {
// 			'bing' {
// 				c.send_message(channel, 'bong!')
// 			}
// 			else {}
// 		}
// 	})
// 	client.start()
//	
// }
// ```

import log
import time
import net.websocket as ws

const url = 'ws://irc-ws.chat.twitch.tv:80'

pub struct TwitchClient {
	channels   []string
	token      string
	username   string
mut:
	client     &ws.Client
	message_cb fn (string, TwitchMessage)
}

pub struct TwitchMessage {
	command    []string = [''] // just for autoskipping
pub:
	user       string
	content	   string
}

// creates a new twitch bot client struct.
[inline]
pub fn new_client(auth_token string, channels []string, username string) ?TwitchClient {
	mut c := ws.new_client(url, read_timeout: 86400 * time.second, logger: &log.Log{level: .fatal} ) or { return none }

	return TwitchClient{
		channels: channels,
		token: auth_token,
		username: username,
		client: c
	}
}

// starts the bot, connects it to the chat server.
[inline]
pub fn (mut t TwitchClient) start() {
	t.client.on_open(fn [t] (mut c ws.Client) ? {
		c.write_string('PASS oauth:$t.token')?
		c.write_string('NICK $t.username')?
	})

	t.client.on_message_ref(message_received, t)

	t.client.connect() or { panic('failed to connect') }
	t.client.listen()  or { panic('cannot start listening') }
}

// registers a callback for what to do when a message is received
pub fn (mut t TwitchClient) on_message(a fn (string, TwitchMessage)) {
	t.message_cb = a
}

// sends a message to the specified channel
[inline]
pub fn (mut t TwitchClient) send_message(channel string, message string) {
	t.client.write_string('PRIVMSG $channel $message') or { panic(err) }
}

[inline]
fn message_received(mut client ws.Client, msg &ws.Message, mut t TwitchClient)? {
	payload := msg.payload.bytestr()
	messages := payload.split('\r\n')

	for i in messages {
		message := parse_message(i)
		match message.command[0] {
			'001' {
				for channel in t.channels {
					client.write_string('JOIN $channel')?
				}
			}
			'PING' {
				client.write_string('PONG $message.content')?
			}
			'NOTICE' {
				eprintln(message)
			}
			'PRIVMSG' {
				t.message_cb(message.command[1], message)
			}
			else {}
		}
	}
}

[inline; direct_array_access]
fn parse_message(s string) TwitchMessage {

	if s.len == 0 { return TwitchMessage{} }

	mut msg := s
	
	mut user := ''
	mut command := []string{}
	mut parameters := ''

	if msg[0..1] == ':' {
		user = msg[1..].all_before(' ').split('!')[0]
		msg = msg.all_after(' ')
	}

	command = msg.all_before(' :').split(' ')

	parameters = msg.all_after(':')
	
	return TwitchMessage { command, user, parameters }
}