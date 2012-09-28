/*  This file is part of Jellyfish.

    Jellyfish is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Jellyfish is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Jellyfish.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef __JELLYFISH_OFFSETS_KEY_VALUE_HPP__
#define __JELLYFISH_OFFSETS_KEY_VALUE_HPP__

#include <jellyfish/misc.hpp>
#include <jellyfish/divisor.hpp>
#include <signal.h>

namespace jellyfish {
/* A word is whatever aligned type used for atomic operations
 * (CAS). Typically, a uint64_t. We store pairs of (key, value), in a
 * bit packed fashion. The key and value can have abritrary size as
 * long as they each fit in one word. A block is the largest number of
 * (key, value) pair such that the first key, and only the first,
 * starts at an aligned word.
 *
 * The key 0x0 is not valid. A key which fits completely within one
 * word is not protected by a "set" bit. A key which straddle the
 * boundary between two aligned words has a set bit in each parts.
 *
 * A value field can have any value and is initialized to 0x0. It has
 * no "set" bit ever.
 *
 * A key is prefixed with a "large" bit. If this bit is 0, the key
 * field is length key_len (not counting the possible set bits) and
 * the value field has length val_len. If the large bit has value 1,
 * the key field is just long enough to encode the number of
 * reprobing hops to go backward to find the actual key. The
 * remainder bits is used for the value field. In this scheme, we
 * assume the length needed to encode the number of reprobes is much
 * less than the length needed to encode the key.
 *
 * The size of the value field, for the normal and large field, is
 * capped at 64. If there is more bits available, they are wasted.
 */

/* Offsets holds all the possible offset for a given combination of
 * key length, value length and reprobe limit.
 */
template<typename word>
class Offsets {
public:
  // woff: offset in words from beginning of block
  // boff: offset in bits within that word. Paste large bit.
  // shift: number of bits stored in first word, or shift to get to beginning of second word
  // cshift: number of bits stored in last word
  // mask1: includes the large bit and the set bit if any.
  // mask2: mask in last word. Contains large and set bit if any. 0 if last word is full
  // sb_mask[12]: mask for set bit in words 1 to last-1 and in last word, if any. set bit is the
  //              last usable bit of the field.
  // lb_mask: mask for the large bit. It is the first bit of the key field.
  typedef struct {
    struct {
      uint_t woff, boff, shift, cshift;
      word   mask1, mask2, sb_mask1, sb_mask2, lb_mask;
    } key;
    struct {
      uint_t woff, boff, shift, cshift;
      word   mask1, mask2;
    } val;
  } offset_t;
  typedef struct {
    offset_t    normal;
    offset_t    large;
  } offset_pair_t;
  struct block_info {
    uint_t len;
    uint_t word_len;
  };
  //    Offsets() {}

  Offsets(uint_t _key_len, uint_t _val_len, uint_t _reprobe_limit) :
    key_len(_key_len),
    val_len(_val_len),
    reprobe_limit(_reprobe_limit),
    reprobe_len(bitsize(reprobe_limit)),
    lval_len(std::min(key_len + val_len - reprobe_len, bsizeof(word))),
    block(compute_offsets()),
    bld(block.len)
  {
    if(val_len > bsizeof(word))
      throw std::runtime_error("Val length must be less than the word size");
    if(_key_len < reprobe_len)
      throw std::runtime_error("Key length must be at least as large as to encode the reprobe_limit");
  }

  ~Offsets() {}

  uint_t get_block_len() const { return block.len; }
  uint_t get_block_word_len() const { return block.word_len; }
  uint_t get_reprobe_len() const { return reprobe_len; }
  uint_t get_key_len() const { return key_len; }
  uint_t get_val_len() const { return val_len; }
  uint_t get_lval_len() const { return lval_len; }
  word   get_max_val(bool large) const { 
    return (((uint64_t)1) << (large ? lval_len : val_len)) - 1;
  }

  // Discretize and round down number of entries according to length
  // of a block. Return in blocks the number of blocks.
  size_t floor_block(size_t entries, size_t &blocks) const {
    blocks = entries / bld;
    return block.len * blocks;
  }

  word *get_word_offset(size_t id, const offset_t **o, const offset_t **lo,
                        word * const base) const {
    uint64_t q, r;
    bld.division(id, q, r);
    word *w = base + (block.word_len * q);
    *o = &offsets[r].normal;
    *lo = &offsets[r].large;
    return w;
  }

private:
  const uint_t     key_len, val_len;
  const uint_t     reprobe_limit, reprobe_len, lval_len;
  const block_info block;
  const divisor64  bld;       // Fast divisor by block.len
  offset_pair_t    offsets[bsizeof(word)];

  block_info compute_offsets();
  bool add_key_offsets(uint_t &cword, uint_t &cboff, uint_t add);
  bool add_val_offsets(uint_t &cword, uint_t &cboff, uint_t add);
  void set_key_offsets(Offsets::offset_t& key, uint_t& cword, uint_t& cboff, uint_t key_len);
  void set_val_offsets(Offsets::offset_t& val, uint_t& cword, uint_t& cboff, uint_t val_len);
  word mask(uint_t length, uint_t shift);
};

template<typename word>
bool Offsets<word>::add_key_offsets(uint_t &cword, uint_t &cboff, uint_t add)
{
  if(cboff + add <= bsizeof(word)) {     // Not spilling over next word
    cboff  = (cboff + add) % bsizeof(word);
    cword += (cboff == 0);
    return false;
  }

  // Span multiple words. Take into account the extra set bit, one in each word
  add   -= bsizeof(word) - cboff - 1; // Substract bits stored in first partial word
  cword += 1 + add / (bsizeof(word) - 1); // Add first word plus any extra complete word
  cboff  = add % (bsizeof(word) - 1); // Extra bits in last word
  cboff += cboff > 0; // Add set bit in last word if use partial word
  return true;
}

template<typename word>
bool Offsets<word>::add_val_offsets(uint_t &cword, uint_t &cboff, uint_t add)
{
  uint_t ocword  = cword;
  cboff         += add;
  cword         += cboff / bsizeof(word);
  cboff          = cboff % bsizeof(word);
  return cword > ocword && cboff > 0;
}

template<typename word>
word Offsets<word>::mask(uint_t length, uint_t shift)
{
  return (((word)1u << length) - 1) << shift;
}

template<typename word>
void Offsets<word>::set_key_offsets(Offsets::offset_t& offset, uint_t& cword, uint_t& cboff, uint_t len) {
  uint_t ocboff;

  offset.key.woff    = cword;
  ocboff             = cboff;
  offset.key.boff    = cboff + 1;
  offset.key.lb_mask = mask(1, cboff);
  if(add_key_offsets(cword, cboff, len + 1)) {
    // Extra bits in last extra word
    offset.key.mask1    = mask(bsizeof(word) - ocboff, ocboff);
    offset.key.mask2    = mask(cboff, 0);
    offset.key.shift    = bsizeof(word) - 1 - ocboff - 1; // -1 for large bit, -1 for set bit
    offset.key.cshift   = cboff ? cboff - 1 : 0;
    offset.key.sb_mask1 = mask(1, bsizeof(word) - 1);
    offset.key.sb_mask2 = cboff ? mask(1, cboff - 1) : 0;
  } else {
    offset.key.mask1    = mask(len + 1, ocboff);
    offset.key.mask2    = 0;
    offset.key.shift    = 0;
    offset.key.cshift   = 0;
    offset.key.sb_mask1 = 0;
    offset.key.sb_mask2 = 0;
  }
}

template <typename word>
void Offsets<word>::set_val_offsets(Offsets::offset_t& offset, uint_t& cword, uint_t& cboff, uint_t len) {
  uint_t ocboff;

  offset.val.woff  = cword;
  offset.val.boff  = cboff;
  ocboff           = cboff;
  if(add_val_offsets(cword, cboff, len)) {
    offset.val.mask1  = mask(bsizeof(uint64_t) - ocboff, ocboff);
    offset.val.mask2  = mask(cboff, 0);
    offset.val.shift  = len - cboff;
    offset.val.cshift = cboff;
  } else {
    offset.val.mask1  = mask(len, ocboff);
    offset.val.mask2  = 0;
    offset.val.shift  = len;
    offset.val.cshift = 0;
  }
}

template<typename word>
typename Offsets<word>::block_info Offsets<word>::compute_offsets()
{
  offset_pair_t *offset = offsets;
  uint_t         cword  = 0;    // current word in block
  uint_t         cboff  = 0;    // current offset in word
  uint_t         lcword;        // idem for large fields
  uint_t         lcboff;

  memset(offsets, '\0', sizeof(offsets));
  do {
    // if(offset - offsets == 25)
    //   asm("int3");

    // Save current offsets as starting point for large key
    lcword = cword;
    lcboff = cboff;

    set_key_offsets(offset->normal, cword, cboff, key_len);
    set_val_offsets(offset->normal, cword, cboff, val_len);

    set_key_offsets(offset->large, lcword, lcboff, reprobe_len);
    set_val_offsets(offset->large, lcword, lcboff, lval_len);

    // ocboff                    = lcboff;
    // offset->large.key.boff    = lcboff + 1;
    // offset->large.key.lb_mask = mask(1, lcboff);
    // if(add_key_offsets(lcword, lcboff, reprobe_len + 1)) {
    //   add_val_offsets(lcword, lcboff, 2);
    //   offset->large.key.mask1    = mask(bsizeof(word) - ocboff, ocboff);
    //   offset->large.key.mask2    = mask(lcboff, 0);
    //   offset->large.key.shift    = reprobe_len + 1 - lcboff;
    //   offset->large.key.cshift   = lcboff - 1;
    //   offset->large.key.sb_mask1 = mask(1, bsizeof(word) - 1);
    //   offset->large.key.sb_mask2 = mask(1, lcboff - 1);
    // } else {
    //   offset->large.key.mask1    = mask(reprobe_len + 1, ocboff);
    //   offset->large.key.mask2    = 0;
    //   offset->large.key.boff     = ocboff + 1; // TODO: this seems unecessary
    //   offset->large.key.shift    = 0;
    //   offset->large.key.cshift   = 0;
    //   offset->large.key.sb_mask1 = 0;
    //   offset->large.key.sb_mask2 = 0;
    // }
    // offset->large.val.woff = lcword;
    // offset->large.val.boff = lcboff;
    // ocboff                 = lcboff;
    // if(add_val_offsets(lcword, lcboff, lval_len)) {
    //   offset->large.val.mask1  = mask(bsizeof(word) - ocboff, ocboff);
    //   offset->large.val.mask2  = mask(lcboff, 0);
    //   offset->large.val.shift  = bsizeof(word) - ocboff;
    //   offset->large.val.cshift = lval_len - offset->large.val.shift;
    // } else {
    //   offset->large.val.mask1  = mask(lval_len, ocboff);
    //   offset->large.val.mask2  = 0;
    //   offset->large.val.shift  = lval_len;
    //   offset->large.val.cshift = 0;
    // }

    offset++;
  } while(cboff != 0 && cboff < bsizeof(word) - 2);

  block_info res = { static_cast<uint_t>(offset - offsets), cword + (cboff == 0 ? 0 : 1) };
  return res;
}
} // namespace jellyfish

#endif // __OFFSETS_KEY_VALUE_HPP__
