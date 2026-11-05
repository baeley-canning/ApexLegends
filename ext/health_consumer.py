r"""health_consumer.py -- the consumer side of the health contract (ext\health_feed.py).

One code path, both producers: the synthetic scenario and the OCR'd HUD go through feed().
Nobody downstream cares where a record came from, which is the whole point - the reader can be
replaced (gio, apexdrv, a screenshot) without touching validation.

Two severities, and the difference is deliberate:
  * error    - the record is unusable and is dropped (schema, ordering, range),
  * anomaly  - the record is usable but the *transition* is impossible in Apex
               (health rising while down, a corpse walking, an entity flipping team).
A consumer that only counts frames proves nothing; a consumer that names the bad transition
does. Read-only, stdlib only, no I/O of its own.
"""
import health_feed as hf

REQUIRED = ('ts', 'seq', 'pid', 'ent', 'name', 'team', 'hp', 'shield', 'state', 'src')
ALLOWED_SRC = ('syn', 'ocr')


class Consumer:
    def __init__(self, hp_max=hf.HP_MAX, shield_max=hf.SHIELD_MAX):
        self.hp_max = hp_max
        self.shield_max = shield_max
        self.frames = 0
        self.errors = []
        self.anomalies = []
        self.entities = {}
        self.respawns = 0
        self.last_seq = None
        self.last_ts = None

    # -- validation ---------------------------------------------------------
    def _schema(self, r):
        for k in REQUIRED:
            if k not in r:
                return 'missing:%s' % k
        for k in ('ts', 'pid', 'team', 'hp', 'shield', 'seq'):
            if not isinstance(r[k], int) and not isinstance(r[k], float):
                return 'type:%s' % k
        for k in ('ent', 'name', 'state', 'src'):
            if not isinstance(r[k], str):
                return 'type:%s' % k
        if r['state'] not in hf.STATES:
            return 'state:%s' % r['state']
        if r['src'] not in ALLOWED_SRC:
            return 'src:%s' % r['src']
        if r['hp'] < 0 or r['hp'] > self.hp_max:
            return 'hp:%d' % r['hp']
        if r['shield'] < 0 or r['shield'] > self.shield_max:
            return 'shield:%d' % r['shield']
        return ''

    def feed(self, r):
        """Accept or reject one record. Returns (accepted, reason)."""
        bad = self._schema(r)
        if bad:
            self.errors.append('%s seq=%s %s' % (bad, r.get('seq'), r.get('ent')))
            return False, bad

        if self.last_seq is not None and r['seq'] <= self.last_seq:
            self.errors.append('seq-not-increasing seq=%s after %s' % (r['seq'], self.last_seq))
            return False, 'seq-not-increasing'
        if self.last_ts is not None and float(r['ts']) < self.last_ts:
            self.errors.append('ts-backwards seq=%s' % r['seq'])
            return False, 'ts-backwards'

        self.last_seq = r['seq']
        self.last_ts = float(r['ts'])
        self.frames += 1

        prev = self.entities.get(r['ent'])
        self._transition(prev, r)
        self.entities[r['ent']] = r
        return True, ''

    def _transition(self, prev, r):
        if prev is None:
            if r['state'] == 'dead':
                self.anomalies.append('born-dead ent=%s' % r['ent'])
            return
        ps, ns = prev['state'], r['state']
        # a 'gone' sample is a PVS drop: team and name are usually not readable, so comparing
        # them across it is a false positive (measured 11:20, bot3 flapped 1 -> -1 -> 1)
        if 'gone' not in (ps, ns):
            if prev['team'] != r['team']:
                self.anomalies.append('team-flap ent=%s %s->%s' % (r['ent'], prev['team'], r['team']))
            if prev['name'] != r['name'] and r['name']:
                self.anomalies.append('renamed ent=%s' % r['ent'])
        if ns == 'alive' and prev['hp'] > 0 and r['hp'] > prev['hp'] and ps == 'alive':
            pass                                     # normal healing, not an anomaly
        if r['hp'] > prev['hp'] and ps in ('downed', 'dead') and ns != 'alive':
            self.anomalies.append('hp-up-while-%s ent=%s' % (ps, r['ent']))
        if ps == 'alive' and ns == 'downed' and r['hp'] > 0:
            self.anomalies.append('downed-with-hp ent=%s hp=%d' % (r['ent'], r['hp']))
        if ps == 'dead' and ns == 'alive':
            self.respawns += 1
        if ps == 'dead' and ns == 'gone':
            self.anomalies.append('corpse-vanished ent=%s' % r['ent'])
        if ps == 'gone' and ns == 'dead':
            self.anomalies.append('reappeared-dead ent=%s' % r['ent'])

    # -- verdict ------------------------------------------------------------
    def report(self):
        if self.errors:
            verdict = 'INGEST_REJECTED'
        elif not self.frames:
            verdict = 'INGEST_EMPTY'
        elif self.anomalies:
            verdict = 'INGEST_ANOMALY'
        else:
            verdict = 'INGEST_OK'
        return {'frames': self.frames, 'entities': len(self.entities),
                'respawns': self.respawns, 'errors': len(self.errors),
                'anomalies': len(self.anomalies), 'verdict': verdict,
                'error_list': self.errors[:10], 'anomaly_list': self.anomalies[:10]}


def consume(records):
    c = Consumer()
    for r in records:
        c.feed(r)
    return c.report()
