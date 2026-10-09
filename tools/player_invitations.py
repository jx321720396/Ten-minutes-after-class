"""离线玩家邀请模型：无人回应时不会自动参加，与 GDScript 保持决策口径一致。"""
import copy
import functools
import weakref


def invitation_behavior(kind):
    def decorate(func):
        @functools.wraps(func)
        def wrapped(core, actor, target, *args, **kwargs):
            if core.player_invitations.intercept(kind, actor, target, args, kwargs):
                return
            return func(core, actor, target, *args, **kwargs)
        return wrapped
    return decorate


class PlayerInvitations:
    def __init__(self, core, kinds, params):
        self._core = weakref.ref(core)
        self.kinds = {row["behavior"]: row["requires_choice"] == "1" for row in kinds}
        self.timeout = int(params["invitation_timeout_ticks"])
        self.cooldown = int(params["invitation_cooldown_ticks"])
        self._pending = None
        self.results = {}
        self.next_allowed = {}
        self.next_id = 1
        self.choice = None

    def intercept(self, kind, actor, target, args, kwargs):
        core = self._core()
        if actor == core.N - 1 or target != core.N - 1 or not self.kinds.get(kind, False):
            return False
        if self.choice and self.choice["actor"] == actor:
            return False
        self.expire()
        if self._pending or core.global_tick < self.next_allowed.get(actor, 0):
            return True
        rec = dict(id=self.next_id, kind=kind, actor=actor, target=target,
                   phase=core.phase_index, expires_tick=core.global_tick + self.timeout,
                   args=args, kwargs=kwargs)
        if not self.valid(rec):
            return True
        self._pending = rec
        self.next_id += 1
        self.next_allowed[actor] = core.global_tick + self.cooldown
        return True

    def valid(self, rec):
        core = self._core()
        if core is None or core.global_tick >= rec["expires_tick"] or core.phase_index != rec["phase"]:
            return False
        if not core.allowed("chat" if rec["kind"] == "join_chat" else rec["kind"]):
            return False
        actor, target = rec["actor"], rec["target"]
        if not (0 <= actor < core.N - 1 and target == core.N - 1):
            return False
        return all(not core.sleeping[i] and core.busy_until[i] <= core.global_tick
                   for i in (actor, target))

    def pending(self):
        if not self._pending or not self.valid(self._pending):
            return {}
        return copy.deepcopy({k: v for k, v in self._pending.items() if k not in ("args", "kwargs")})

    def expire(self):
        if self._pending and not self.valid(self._pending):
            self.results[self._pending["id"]] = dict(ok=False, error="invitation_expired")
            self._pending = None

    def respond(self, invitation_id, accepted):
        self.expire()
        if invitation_id in self.results:
            return copy.deepcopy(self.results[invitation_id])
        if not self._pending or self._pending["id"] != invitation_id:
            return dict(ok=False, error="unknown_invitation")
        rec = self._pending
        self._pending = None
        core = self._core()
        self.choice = dict(actor=rec["actor"], accepted=bool(accepted))
        try:
            if accepted or rec["kind"] in ("ask_help", "apologize", "join_chat"):
                getattr(core, "do_" + rec["kind"])(rec["actor"], rec["target"],
                                                *rec["args"], **rec["kwargs"])
        finally:
            self.choice = None
        result = dict(ok=True, id=invitation_id, accepted=bool(accepted), kind=rec["kind"])
        self.results[invitation_id] = result
        return copy.deepcopy(result)

    def choice_for(self, actor):
        if self.choice and self.choice["actor"] == actor:
            return self.choice["accepted"]
        return None

    def authorizes(self, actor):
        return self.choice_for(actor) is True

    def is_waiting(self, actor):
        return bool(self._pending and self._pending["actor"] == actor and self.valid(self._pending))
