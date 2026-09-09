/**
 * ⚠ EXPERIMENTAL / NOT WIRED (audit §1.4): the canonical call engine is
 * the Jitsi embed in pages/room.js — chosen explicitly in Phase 80.
 * This mesh prototype is kept as reference for a future self-hosted
 * engine; nothing imports it today.
 *
 * WDOS Call Fabric (Phase 78) — video calls that never leave WODDI.
 * A WebRTC mesh (each participant connects to each) signalled entirely
 * through the org's own Supabase realtime channel. No external call
 * servers; only public STUN for address discovery. Best for rooms of
 * up to ~8 people — WODDI's leadership circles, not stadiums.
 */
import { db } from './db.js';

const ICE = { iceServers: [
  { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] },
] };

export function createCall(roomId, me, callbacks) {
  const { onTrack, onLeave, onPeers, onState } = callbacks;
  const myId = me.id + ':' + Math.random().toString(36).slice(2, 7);
  const peers = new Map();   // peerKey -> { pc, name }
  let channel = null;
  let localStream = null;
  let closed = false;

  function say(type, to, payload) {
    channel?.send({ type: 'broadcast', event: 'rtc',
      payload: { type, from: myId, fromName: me.name, to, ...payload } });
  }

  function peerFor(key, name) {
    if (peers.has(key)) return peers.get(key);
    const pc = new RTCPeerConnection(ICE);
    const entry = { pc, name: name || '' };
    peers.set(key, entry);
    for (const track of localStream?.getTracks() || []) {
      pc.addTrack(track, localStream);
    }
    pc.onicecandidate = (e) => {
      if (e.candidate) say('ice', key, { candidate: e.candidate.toJSON() });
    };
    pc.ontrack = (e) => onTrack?.(key, entry.name, e.streams[0]);
    pc.onconnectionstatechange = () => {
      onState?.(key, pc.connectionState);
      if (['failed', 'closed', 'disconnected'].includes(pc.connectionState)) {
        // give ICE a moment; drop on hard states
        if (pc.connectionState !== 'disconnected') drop(key);
      }
    };
    onPeers?.(peers.size);
    return entry;
  }

  function drop(key) {
    const p = peers.get(key);
    if (!p) return;
    try { p.pc.close(); } catch { /* gone */ }
    peers.delete(key);
    onLeave?.(key);
    onPeers?.(peers.size);
  }

  async function handle(msg) {
    if (closed || msg.from === myId) return;
    if (msg.to && msg.to !== myId) return;
    if (msg.type === 'hello') {
      // newcomer announces; existing peers offer
      const { pc } = peerFor(msg.from, msg.fromName);
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      say('offer', msg.from, { sdp: pc.localDescription.toJSON
        ? pc.localDescription.toJSON() : pc.localDescription });
    } else if (msg.type === 'offer') {
      const { pc } = peerFor(msg.from, msg.fromName);
      await pc.setRemoteDescription(msg.sdp);
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      say('answer', msg.from, { sdp: pc.localDescription.toJSON
        ? pc.localDescription.toJSON() : pc.localDescription });
    } else if (msg.type === 'answer') {
      const p = peers.get(msg.from);
      if (p) await p.pc.setRemoteDescription(msg.sdp);
    } else if (msg.type === 'ice') {
      const p = peers.get(msg.from);
      if (p && msg.candidate) {
        try { await p.pc.addIceCandidate(msg.candidate); } catch { /* late */ }
      }
    } else if (msg.type === 'bye') {
      drop(msg.from);
    }
  }

  const extra = new Map();   // event -> fn, attached before subscribe
  return {
    myId,
    on(event, fn) { extra.set(event, fn); },
    async join(stream) {
      localStream = stream;
      channel = db().channel(`call-${roomId}`, {
        config: { broadcast: { self: false } } });
      channel.on('broadcast', { event: 'rtc' },
        ({ payload }) => { handle(payload).catch(() => {}); });
      for (const [event, fn] of extra) {
        channel.on('broadcast', { event },
          ({ payload }) => fn(payload));
      }
      await new Promise((res) => {
        channel.subscribe((st) => { if (st === 'SUBSCRIBED') res(); });
      });
      say('hello', null, {});
    },
    /** piggyback data (captions) on the same channel */
    send(event, payload) {
      channel?.send({ type: 'broadcast', event, payload });
    },
    leave() {
      closed = true;
      say('bye', null, {});
      for (const key of [...peers.keys()]) drop(key);
      try { db().removeChannel(channel); } catch { /* gone */ }
      for (const tr of localStream?.getTracks() || []) {
        try { tr.stop(); } catch { /* gone */ }
      }
    },
  };
}
