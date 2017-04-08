# -*- coding: UTF-8 -*-
# cython: language_level=3, c_string_type=str, c_string_encoding=ascii

from __future__ import unicode_literals

from cython.operator cimport dereference as deref, address

from libcpp cimport bool
from libc.stdint cimport uint32_t

from ._minhash cimport KmerMinHash, KmerMinAbundance, _hash_murmur
import math


cdef uint32_t MINHASH_DEFAULT_SEED = 42


cdef bytes to_bytes(s):
    if not isinstance(s, (basestring, bytes)):
        raise TypeError("Requires a string-like sequence")

    if isinstance(s, unicode):
        s = s.encode('utf-8')
    return s


def hash_murmur(kmer, uint32_t seed=MINHASH_DEFAULT_SEED):
    "hash_murmur(string, [,seed])\n\n"
    "Compute a hash for a string, optionally using a seed (an integer). "
    "The current default seed is returned by hash_seed()."

    return _hash_murmur(to_bytes(kmer), seed)


def dotproduct(a, b, normalize=True):
    """
    Compute the dot product of two dictionaries {k: v} where v is
    abundance.
    """

    if normalize:
        norm_a = math.sqrt(sum([ x*x for x in a.values() ]))
        norm_b = math.sqrt(sum([ x*x for x in b.values() ]))

        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
    else:
        norm_a = 1.0
        norm_b = 1.0

    prod = 0.
    for k, abundance in a.items():
        prod += (float(abundance) / norm_a) * (b.get(k, 0) / norm_b)

    return prod


cdef class MinHash(object):

    def __init__(self, unsigned int n, unsigned int ksize,
                       bool is_protein=False,
                       bool track_abundance=False,
                       uint32_t seed=MINHASH_DEFAULT_SEED,
                       HashIntoType max_hash=0):
        self.track_abundance = track_abundance
        self.hll = None

        cdef KmerMinHash *mh = NULL
        if track_abundance:
            mh = new KmerMinAbundance(n, ksize, is_protein, seed, max_hash)
        else:
            mh = new KmerMinHash(n, ksize, is_protein, seed, max_hash)

        self._this.reset(mh)

    def __copy__(self):
        a = MinHash(deref(self._this).num, deref(self._this).ksize,
                    deref(self._this).is_protein, self.track_abundance,
                    deref(self._this).seed, deref(self._this).max_hash)
        a.merge(self)
        return a


    def __getstate__(self):             # enable pickling
        with_abundance = False
        if self.track_abundance:
            with_abundance = True

        return (deref(self._this).num,
                deref(self._this).ksize,
                deref(self._this).is_protein,
                self.get_mins(with_abundance=with_abundance),
                self.hll, self.track_abundance, deref(self._this).max_hash,
                deref(self._this).seed)

    def __setstate__(self, tup):
        (n, ksize, is_protein, mins, hll, track_abundance, max_hash, seed) =\
          tup

        self.track_abundance = track_abundance
        self.hll = hll

        cdef KmerMinHash *mh = NULL
        if track_abundance:
            mh = new KmerMinAbundance(n, ksize, is_protein, seed, max_hash)
            self._this.reset(mh)
            self.set_abundances(mins)
        else:
            mh = new KmerMinHash(n, ksize, is_protein, seed, max_hash)
            self._this.reset(mh)
            self.add_many(mins)

    def __richcmp__(self, other, op):
        if op == 2:
            return self.__getstate__() == other.__getstate__()
        raise Exception("undefined comparison")

    def copy_and_clear(self):
        a = MinHash(deref(self._this).num, deref(self._this).ksize,
                    deref(self._this).is_protein, self.track_abundance,
                    deref(self._this).seed, deref(self._this).max_hash)
        return a

    def add_sequence(self, sequence, bool force=False):
        deref(self._this).add_sequence(to_bytes(sequence), force)

    def add(self, kmer):
        "Add kmer into sketch."
        self.add_sequence(kmer)

    def add_many(self, hashes):
        "Add many hashes in at once."
        for hash in hashes:
            self.add_hash(hash)

    def update(self, other):
        "Update this estimator from all the hashes from the other."
        self.add_many(other.get_mins())

    def __len__(self):
        return deref(self._this).num

    cpdef get_mins(self, bool with_abundance=False):
        cdef KmerMinAbundance *mh = <KmerMinAbundance*>address(deref(self._this))
        if with_abundance and self.track_abundance:
            return mh.mins
        elif self.track_abundance:
            return [it.first for it in mh.mins]
        else:
            return [it for it in deref(self._this).mins]

    def get_hashes(self):
        return self.get_mins()

    @property
    def seed(self):
        return deref(self._this).seed

    @property
    def num(self):
        return deref(self._this).num

    @property
    def is_protein(self):
        return deref(self._this).is_protein

    @property
    def ksize(self):
        return deref(self._this).ksize

    @property
    def max_hash(self):
        mm = deref(self._this).max_hash
        if mm == 18446744073709551615:
            return 0
        return mm

    def add_hash(self, uint64_t h):
        deref(self._this).add_hash(h)

    def count_common(self, MinHash other):
        cdef KmerMinAbundance *mh = NULL
        cdef KmerMinAbundance *other_mh = NULL
        cdef uint64_t n = 0

        if self.track_abundance:
            mh = <KmerMinAbundance*>address(deref(self._this))
            if other.track_abundance:
                other_mh = <KmerMinAbundance*>address(deref(other._this))
                n = mh.count_common(deref(other_mh))
            else:
                n = mh.count_common(deref(other._this))
        else:
            if other.track_abundance:
                other_mh = <KmerMinAbundance*>address(deref(other._this))
                n = other_mh.count_common(deref(self._this))
            else:
                n = deref(self._this).count_common(deref(other._this))

        return n

    def compare(self, MinHash other):
        n = self.count_common(other)
        size = max(deref(self._this).size(), 1)
        return n / size

    def jaccard(self, MinHash other):
        return self.compare(other)

    def similarity(self, other, ignore_abundance=False):
        """\
        Calculate similarity of two sketches.

        If the sketches are not abundance weighted, or ignore_abundance=True,
        compute Jaccard similarity.

        If the sketches are abundance weighted, calculate a distance metric
        based on the cosine similarity.

        Note, because the term frequencies (tf-idf weights) cannot be negative,
        the angle will never be < 0deg or > 90deg.

        See https://en.wikipedia.org/wiki/Cosine_similarity
        """

        if not self.track_abundance or ignore_abundance:
            return self.jaccard(other)
        else:
            a = self.get_mins(with_abundance=True)
            b = other.get_mins(with_abundance=True)

            prod = dotproduct(a, b)
            prod = min(1.0, prod)

            distance = 2*math.acos(prod) / math.pi
            return 1.0 - distance

    def similarity_ignore_maxhash(self, MinHash other):
        a = set(self.get_mins())

        b = set(other.get_mins())

        overlap = a.intersection(b)
        return float(len(overlap)) / float(len(a))

    def __iadd__(self, MinHash other):
        cdef KmerMinAbundance *mh = <KmerMinAbundance*>address(deref(self._this))
        cdef KmerMinAbundance *other_mh = <KmerMinAbundance*>address(deref(other._this))
        if self.track_abundance:
             mh.merge(deref(other_mh))
        else:
            deref(self._this).merge(deref(other._this))

        return self
    merge = __iadd__

    cpdef set_abundances(self, dict values):
        if self.track_abundance:
            for k, v in values.items():
                (<KmerMinAbundance*>address(deref(self._this))).mins[k] = v
        else:
            raise RuntimeError("Use track_abundance=True when constructing "
                               "the MinHash to use set_abundances.")

    def add_protein(self, sequence):
        cdef uint32_t ksize = deref(self._this).ksize // 3
        if len(sequence) < ksize:
            return

        if not deref(self._this).is_protein:
            raise ValueError("cannot add amino acid sequence to DNA MinHash!")

        for i in range(0, len(sequence) - ksize + 1):
            deref(self._this).add_word(to_bytes(sequence[i:i + ksize]))

    def is_molecule_type(self, molecule):
        if molecule == 'dna' and not self.is_protein:
            return True
        if molecule == 'protein' and self.is_protein:
            return True
        return False
