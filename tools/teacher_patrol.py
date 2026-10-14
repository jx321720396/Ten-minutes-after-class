"""非社交节点的老师巡查与没收账本，随机数只使用内核 RNG。"""
class TeacherPatrol:
    def __init__(self, params, count):
        self.params = params
        self.present = False
        self.visited = False
        self.leave_tick = -1
        self.confiscated = [0] * count
        self.exemption_tokens = [0] * count
        self.exempt_this_visit = [False] * count
        self.events = []

    def begin_phase(self, core):
        self.present = core.phase == "class"
        self.visited = False
        self.leave_tick = -1
        self.exempt_this_visit = [False] * core.N

    def step(self, core):
        if core.phase != "break":
            return
        if self.present and core.global_tick >= self.leave_tick:
            self.present = False
            self.events.append(dict(kind="teacher_left"))
        tick = core.tick_in_phase + 1
        if self.visited or tick not in (int(self.params["visit_check_first"]), int(self.params["visit_check_second"])):
            return
        if core.rng.random() >= self.params["visit_p"]:
            return
        self.visited = self.present = True
        self.leave_tick = core.global_tick + int(self.params["stay_ticks"])
        self.events.append(dict(kind="teacher_arrived"))
        for i in range(core.N):
            if not core.is_present(i) or core.sleeping[i] or core.current_act[i] == "study":
                continue
            core.apply_event(i, i, "teacher_visit_stress")
            if core.busy_act[i] in ("listen_music", "eat_snack"):
                self.events.append(dict(kind="teacher_caught", i=i))
            self.catch_reader(core, i)

    def catch_reader(self, core, i):
        if not self.present or core.phase != "break" or not core.is_present(i) or core.sleeping[i]:
            return False
        if core.busy_act[i] != "read_book" or core.book[i] <= 0 or self.exempt_this_visit[i]:
            return False
        if self.exemption_tokens[i] > 0:
            self.exemption_tokens[i] -= 1
            self.exempt_this_visit[i] = True
            self.events.append(dict(kind="book_confiscation_exempted", i=i))
            return False
        amount = min(int(self.params["confiscate_books_per_catch"]), core.book[i])
        core.book[i] -= amount
        self.confiscated[i] += amount
        core.current_act[i] = core.busy_act[i] = None
        core.busy_phase[i] = -1
        core.busy_until[i] = core.global_tick
        core.in_conversation[i] = False
        core.stats["book_confiscations"] = core.stats.get("book_confiscations", 0) + amount
        self.events.append(dict(kind="book_confiscated", i=i, amount=amount,
                                books=core.book[i], confiscated_books=self.confiscated[i]))
        return True

    def multiplier(self, kind):
        if self.present and kind in ("roughhouse",):
            return self.params["suppress_behavior_mult"]
        return 1.0
