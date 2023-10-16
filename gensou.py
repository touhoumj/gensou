#!/usr/bin/env python3

import csv
import io
import logging
import time
from collections import OrderedDict
from functools import wraps, lru_cache
from typing import Dict, Optional
from pydantic import BaseModel, computed_field, Field
from flask import Flask, g, request, has_request_context
from flask.logging import default_handler

app = Flask(__name__)


def now():
    return int(time.time())


class Player(BaseModel):
    namequote: Optional[str] = None
    name: str
    hash: str
    pin: str
    chara_id: str
    chara_skin: int
    chrhash: str
    gamever: str
    titletext: str
    trip: str
    places: str
    mode: str
    titletype: int
    standby: bool = False
    disconnected: bool = False
    loading: int = 0
    last_activity_time: Optional[int] = None

    @computed_field
    @property
    def timedout(self) -> bool:
        return (
            self.last_activity_time is not None
            and self.last_activity_time < now() - TIMEOUT
        )

    def __hash__(self) -> str:
        return self.hash.__hash__()


class Room(BaseModel):
    roomnum: int
    time: int
    roomname: str
    length: int
    takuname: str
    usemagic: bool
    roomcomment: str
    password: bool
    pass_: Optional[str] = Field(default=None, alias="pass")
    status: str
    gamestart: bool = False
    players: OrderedDict[str, Player] = OrderedDict()
    events: Dict[int, str] = {}

    @computed_field
    @property
    def playercount(self) -> int:
        return len(self.players)

    def __hash__(self) -> int:
        return self.roomnum


# Global server state and also the reason why the server only works on a single-thread
lobby: OrderedDict[int, Room] = OrderedDict()
TIMEOUT = 45


def should_remove_room(room):
    return all(
        player.disconnected or player.timedout
        for player in room.players.values()
        if player.trip != "CPU"
    )


def maybe_remove_room(room):
    if should_remove_room(room):
        app.logger.info("removing room '%s'", room.roomname)
        lobby.pop(room.roomnum, None)


def is_player_the_room_owner(room, player):
    return len(room.players) > 0 and next(iter(room.players.keys())) == player.hash


def remove_cpu_players(players):
    return OrderedDict((k, v) for k, v in players.items() if v.trip != "CPU")


def rows_to_csv_string(rows, header):
    output = io.StringIO()
    writer = csv.DictWriter(
        output, fieldnames=header, extrasaction="ignore", quoting=csv.QUOTE_NONNUMERIC
    )
    writer.writeheader()
    writer.writerows(row.model_dump(include=header) for row in rows)
    return output.getvalue()


@lru_cache(maxsize=100)
def log_disconnected_player(room, player):
    app.logger.info(
        "player '%s' disconnected during a game '%s'",
        player.name,
        room.roomname,
    )


def room_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        room_id = kwargs.get("room_id", request.form.get("roomnum", type=int))
        if room_id is None:
            app.logger.error("room ID not provided")
            return "room ID not provided", 403

        g.room = lobby.get(room_id)
        if g.room is None:
            app.logger.error("room not found: %s: %s", room_id, dict(request.form))
            return "room not found", 404

        return f(*args, **kwargs)

    return decorated_function


def player_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        hash = kwargs.get("hash", request.form.get("hash"))
        if hash is None:
            return "player hash not provided", 403

        g.player = g.room.players.get(hash)
        if g.player is None:
            app.logger.error("player not found %s: %s", hash, dict(request.form))
            return "player not found", 404

        return f(*args, **kwargs)

    return decorated_function


# Used to set the message in the main menu (can be anything)
@app.route("/thmj4n/title.txt")
def title():
    return f"Connected to a test server at {request.host}\n"


# Every request with a payload is sent through this endpoint
@app.route("/index.php", methods=["POST"])
def index():
    app.logger.debug("%s", dict(request.form))

    match request.form.get("func"):
        case "net_lobby":
            return list_rooms()
        case "net_quick":
            return quick_join()
        case "room_refresh":
            return refresh_room()
        case "room_create":
            return create_room()
        case "room_join":
            return join_room()
        case "room_leave":
            return leave_room()
        case "room_standby":
            return room_standby()
        case "game_loading":
            return player_loading_state()
        case "game_taskrecv":
            return record_game_event()
        case "game_taskcheck":
            return list_disconnected_players()
        case "game_leave":
            return leave_game()
        case "game_finish":
            return finish_game()
        case _:
            app.logger.warning("unhandled request: %s", dict(request.form))
            return "invalid function", 404


# list game rooms
#
# POST /index.php
# form_data = {
#     "func": "net_lobby",
#     "gamever": "4.28",
#     "vdate": "20140830223544",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
# }
# returns 200 with no body or a csv with a list of rooms
#   roomnum,time,roomname,length,takuname,usemagic,roomcomment,password,status,playercount\n
#   1697043915,12,"koko",1,default,false,"",false,waiting,0\n
def list_rooms():
    to_remove = [room for room in lobby.values() if should_remove_room(room)]
    for room in to_remove:
        app.logger.info("removing room '%s' due to inactivity", room.roomname)
        lobby.pop(room.roomnum, None)

    fields = [
        "roomnum",
        "time",
        "roomname",
        "length",
        "takuname",
        "usemagic",
        "roomcomment",
        "password",
        "status",
        "playercount",
    ]
    rows = lobby.values()
    body = rows_to_csv_string(rows, fields)

    return body


# room keepalive
#
# POST /index.php
# form_data = {
#     "vdate": "20140830223544",
#     "gamever": "4.28",
#     "func": "room_refresh",
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "roomnum": "1697409506",
# }
# the response body is not checked
@room_required
@player_required
def refresh_room():
    g.player.last_activity_time = now()
    return "ok."


# create room
#
# POST /index.php
# form_data = {
#     "roomname": "asoko",
#     "time": "15",
#     "tweetflag": "false",
#     "vdate": "20140830223544",
#     "length": "2",
#     "gamever": "4.28",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "password": "false",
#     "usemagic": "true",
#     "takuname": "makai",
#     "pass": "",
#     "func": "room_create",
#     "roomcomment": "",
#     "quickaccept": "true",
#     "_time_index": "3",
# }
# returns 200 with string 'ok.' and the room ID on the 2nd line
#   ok.\n
#   1697043915
def create_room():
    room_id = now()
    room = Room(roomnum=room_id, status="waiting", **request.form)
    lobby[room_id] = room
    body = f"ok.\n{room_id}"
    app.logger.info("created room '%s'", room.roomname)

    return body


# quick match
#
# POST /index.php
# form_data = {
#     "vdate": "20140830223544",
#     "func": "net_quick",
#     "gamever": "4.28",
#     "name": "New Player",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
# }
def quick_join():
    app.logger.error("called unimplemented function quick_join: %s", dict(request.form))
    return ""


# join room
#
# POST /index.php
# form_data = {
#     "namequote": '"New Player"',
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "chara_skin": "1",
#     "chrhash": "luna1",
#     "pass": "",
#     "gamever": "4.28",
#     "titletext": "",
#     "chara_id": "luna",
#     "trip": "R6TmeM6eev",
#     "places": "0 games  360pt  0 wins",
#     "mode": "default",
#     "roomnum": "1697409506",
#     "func": "room_join",
#     "titletype": "4",
#     "name": "New Player",
#     "vdate": "20140830223544",
# }
@room_required
def join_room():
    pass_ = request.form.get("pass", type=str)
    # length 1: 4-player tonpuusen
    # length 2: 4-player hanchan
    # length 3: 3-player hanchan
    max_players = 3 if g.room.length == 3 else 4
    if g.room.password and g.room.pass_ != pass_:
        app.logger.warning(
            "failed to join the room (invalid password): %s", dict(request.form)
        )
        return "invalid password", 403

    if g.room.playercount >= max_players:
        app.logger.warning(
            "failed to join the room (room is full): %s", dict(request.form)
        )
        return "room is full", 403

    player = Player(**request.form)
    g.room.players[player.hash] = player
    app.logger.info(
        "player '%s' joined the room '%s'",
        player.name,
        g.room.roomname,
    )
    return "OK"


# leave room
#
# POST /index.php
# form_data = {
#     "vdate": "20140830223544",
#     "func": "room_leave",
#     "pass": "",
#     "gamever": "4.28",
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "roomnum": "1697379007",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
# }
@room_required
@player_required
def leave_room():
    g.room.players.pop(g.player.hash, None)
    g.room.players = remove_cpu_players(g.room.players)
    app.logger.info(
        "player '%s' left the room '%s'",
        g.player.name,
        g.room.roomname,
    )
    maybe_remove_room(g.room)
    return "OK"


# leave game
#
# POST /index.php
# form_data = {
#     "vdate": "20140830223544",
#     "func": "game_leave",
#     "pass": "",
#     "gamever": "4.28",
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "roomnum": "1697410036",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
# }
@room_required
@player_required
def leave_game():
    g.player.disconnected = True
    app.logger.info(
        "player '%s' left the game '%s'",
        g.player.name,
        g.room.roomname,
    )
    maybe_remove_room(g.room)
    return "ok."


# set player ready state
#
# POST /index.php
# form_data = {
#     "standby": "false",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "vdate": "20140830223544",
#     "pass": "",
#     "func": "room_standby",
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "gamever": "4.28",
#     "roomnum": "1697409506",
# }
@room_required
@player_required
def room_standby():
    standby = request.form.get("standby") == "true"

    if is_player_the_room_owner(g.room, g.player):
        app.logger.info(
            "player '%s' started the room '%s'",
            g.player.name,
            g.room.roomname,
        )
        for player in g.room.players.values():
            player.standby = standby
    else:
        g.player.standby = standby
        app.logger.info(
            "player '%s' is %s in room '%s'",
            g.player.name,
            "ready" if g.player.standby else "not ready",
            g.room.roomname,
        )

    return "ok."


# set player loading state
#
# POST /index.php
# form_data = {
#     "vdate": "20140830223544",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "gamever": "4.28",
#     "pass": "",
#     "func": "game_loading",
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "loading": "100",
#     "roomnum": "1697410036",
# }
@room_required
@player_required
def player_loading_state():
    g.room.status = "playing"
    loading = request.form.get("loading", type=int)
    if loading is None:
        return "missing loading state", 403

    g.player.loading = loading
    g.player.last_activity_time = now()
    app.logger.debug(
        "player '%s' in room '%s' is loading: %s",
        g.player.name,
        g.room.roomname,
        g.player.loading,
    )
    return "ok."


# receive game event
#
# POST /index.php
# form_data = {
#     "snum": "325",
#     "q": 'N={};N["seat"]=2;N["tag"]="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";N["roomnum"]=1697411428;N["task"]="ActSutehai";N["env"]={};N["env"]["reach"]=false;N["env"]["index"]=13;return N;',
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "roomnum": "1697411428",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "pass": "",
#     "gamever": "4.28",
#     "vdate": "20140830223544",
#     "seat": "2",
#     "func": "game_taskrecv",
# }
@room_required
@player_required
def record_game_event():
    seat = request.form.get("seat")
    event_id = request.form.get("snum", type=int)
    event = request.form.get("q")
    if None in [seat, event_id, event]:
        return "missing required parameters", 403

    app.logger.debug(
        "player '%s' sent an event '%s' for room '%s'",
        g.player.name,
        event_id,
        g.room.roomname,
    )
    # S/SCENE/NETWORK.LUA:231
    if event_id in g.room.events:
        return "TASK_REGISTED"

    g.room.events[event_id] = event
    return "OK"


# list disconnected players
#
# POST /index.php
# form_data = {
#     "seat": "1",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "vdate": "20140830223544",
#     "pass": "",
#     "func": "game_taskcheck",
#     "hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
#     "gamever": "4.28",
#     "roomnum": "1697411428",
# }
@room_required
@player_required
def list_disconnected_players():
    g.player.last_activity_time = now()
    # S/SCENE/NETWORK.LUA:82
    disconnected_players = [
        player
        for player in g.room.players.values()
        if player.disconnected or player.timedout
    ]
    for player in disconnected_players:
        log_disconnected_player(g.room, player)

    body = "\n".join(player.hash for player in disconnected_players)
    return body


# end the game
#
# POST /index.php
# form_data = {
#     "snum": "327",
#     "pin": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
#     "pass": "",
#     "func": "game_finish",
#     "vdate": "20140830223544",
#     "gamever": "4.28",
#     "roomnum": "1697411428",
# }
@room_required
def finish_game():
    app.logger.debug("game '%s' ended", g.room.roomname)
    lobby.pop(g.room.roomnum, None)
    return "ok."


@app.route("/rooms/<int:version>/<int:room_id>/info")
@room_required
def room_info(version, room_id):
    fields = ["gamestart"]
    body = rows_to_csv_string([g.room], fields)
    return body


@app.route("/rooms/<int:version>/<int:room_id>/users")
@room_required
def room_players(version, room_id):
    fields = [
        "name",
        "hash",
        "titletext",
        "titletype",
        "chara_id",
        "chara_skin",
        "places",
        "trip",
        "standby",
    ]
    to_kick = [
        player
        for player in g.room.players.values()
        if player.disconnected or player.timedout
    ]
    for player in to_kick:
        app.logger.info(
            "removing player '%s' from room '%s' due to inactivity",
            player.name,
            g.room.roomname,
        )
        g.room.players.pop(player.hash)

    body = rows_to_csv_string(g.room.players.values(), fields)
    return body


@app.route("/rooms/<int:version>/<int:room_id>/loading_<hash>")
@room_required
@player_required
def room_loading_state(version, room_id, hash):
    body = str(g.player.loading)
    return body


@app.route("/rooms/<int:version>/<int:room_id>/tasknum")
@room_required
def latest_room_event_id(version, room_id):
    if len(g.room.events) > 0:
        latest_event_id = max(g.room.events.keys())
    else:
        latest_event_id = 0

    return str(latest_event_id)


@app.route("/rooms/<int:version>/<int:room_id>/task_<int:event_id>")
@room_required
def room_event(version, room_id, event_id):
    event = g.room.events.get(event_id)
    if event:
        # S/SCENE/NETWORK.LUA:146
        return f"task:{event_id}:{event}"
    else:
        return "event not found", 404


class RequestFormatter(logging.Formatter):
    format = (
        "[%(asctime)s] [%(levelname)s] %(remote_addr)s %(method)s %(path)s: %(message)s"
    )
    grey = "\x1b[38;20m"
    cyan = "\x1b[36;20m"
    yellow = "\x1b[33;20m"
    red = "\x1b[31;20m"
    bold_red = "\x1b[31;1m"
    reset = "\x1b[0m"

    FORMATS = {
        logging.DEBUG: cyan + format + reset,
        logging.INFO: grey + format + reset,
        logging.WARNING: yellow + format + reset,
        logging.ERROR: red + format + reset,
        logging.CRITICAL: bold_red + format + reset,
    }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno)
        formatter = logging.Formatter(log_fmt)

        if has_request_context():
            record.method = request.method
            record.path = request.path
            record.remote_addr = request.remote_addr
        else:
            record.method = None
            record.path = None
            record.remote_addr = None

        return formatter.format(record)


default_handler.setFormatter(RequestFormatter())
app.logger.setLevel(logging.INFO)


if __name__ == "__main__":
    app.logger.setLevel(logging.DEBUG)
    app.run()
