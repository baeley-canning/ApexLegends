#pragma once

// ============================================================================
// apex_offsets_generated.h - THE authoritative offset table (PLAN stage 2).
//
// Rule (FACTS.md): nothing here may be used to draw until it is marked PROVEN,
// and PROVEN means "validated numerically in a live match", not "it read a
// plausible number". Both candidate sets that exist in the tree are listed so
// the conflict is visible instead of hidden in two different files:
//
//   A) memory.h / features.cpp  (2026-10-25, pre-Javelin notes)
//   B) ext/h320_va.py           (2026-11-07, a0 offsets, never run green)
//
// The two disagree on EVERY per-entity field and on the view matrix, which is
// why an external ESP would draw nothing even with a perfect read path.
//
// Stage 2 procedure:
//   1. qk_probe --pe on the live game  -> module base + build stamp
//   2. read ENTITY_LIST, walk 0..0x2000 slots in READ8 batches of 64
//   3. for each non-null slot, read a 0x1200 entity page once and look for the
//      known-good values (hp/shield 100.0f or 100, a team id, a name pointer)
//   4. project a candidate origin with the candidate matrix and compare against
//      a screenshot of the same dummy  -> the only accepted proof
//   5. promote the winner to PROVEN, delete the loser.
// ============================================================================

#include <cstdint>

namespace ApexOffsetsGen {

// --- module-level (RVA from the main image base) ---------------------------
// CANDIDATE: two sources agree, never measured live.
constexpr uint32_t ENTITY_LIST          = 0x23F6A90;  // A+B agree
constexpr uint32_t LOCAL_PLAYER          = 0x01E7D4B8; // A only

// CANDIDATE: B. A's value (0x022EE01) is the RVA of VTP_GetEngineTraceClient
// - it is code, and reading 64 bytes there can never be a valid matrix.
constexpr uint32_t VIEW_MATRIX           = 0x1B4DFA0;  // B
constexpr uint32_t VIEW_MATRIX_A_BAD     = 0x022EE01;  // A - known wrong, keep for the diff

// --- per-entity (from the entity pointer) --------------------------------
// A and B disagree completely. Neither is proven. A entity is expected to be
// one of the game's "player" objects; B's field set looks like a full player
// struct (name pointer at +0x10F0), which is the more plausible of the two.
constexpr uint32_t ENT_ORIGIN_B          = 0x0330;   // B (Vec3)
constexpr uint32_t ENT_ORIGIN_A          = 0x0258;   // A (Vec3)
constexpr uint32_t ENT_HP_B              = 0x05E0;   // B (int32?)
constexpr uint32_t ENT_SHIELD_B          = 0x05E8;   // B
constexpr uint32_t ENT_ALIVE_B           = 0x05DC;   // B
constexpr uint32_t ENT_TEAM_B            = 0x10E8;   // B
constexpr uint32_t ENT_NAME_B            = 0x10F0;   // B (pointer)
constexpr uint32_t ENT_TEAM_A            = 0x0478;   // A
constexpr uint32_t ENT_HEALTH_A          = 0x03A0;   // A

// --- sweep geometry (Stage 2) --------------------------------------------
// Entity slots are a dense array of pointers; 0x2000 slots is far beyond the
// live player count and costs 128 READ8 batches per frame at worst.
constexpr uint32_t ENTITY_SLOT_STRIDE     = 8;
constexpr uint32_t ENTITY_SLOT_MAX        = 0x2000;

} // namespace ApexOffsetsGen
