// SPDX-License-Identifier: GPL-2.0
//
// generator.c - a generator for test with buffers of PCM frames.
//
// Copyright (c) 2018 Takashi Sakamoto <o-takashi@sakamocchi.jp>
//
// Licensed under the terms of the GNU General Public License, version 2.

#ifndef __ALSA_UTILS_AXFER_TEST_GENERATOR__H_
#define __ALSA_UTILS_AXFER_TEST_GENERATOR__H_

#include <stdint.h>
#include <alsa/asoundlib.h>

struct test_generator;
typedef int (*generator_cb_t)(struct test_generator *gen,
			      snd_pcm_access_t access,
			      snd_pcm_format_t sample_format,
			      unsigned int samples_per_frame,
			      void *frame_buffer, unsigned int frame_count);

struct test_generator {
	int fd;
	uint64_t access_mask;
	uint64_t sample_format_mask;
	unsigned int min_samples_per_frame;
	unsigned int max_samples_per_frame;
	unsigned int min_frame_count;
	unsigned int max_frame_count;
	unsigned int step_frame_count;

	generator_cb_t cb;
	void *private_data;
};

int generator_context_init(struct test_generator *gen,
			   uint64_t access_mask, uint64_t sample_format_mask,
			   unsigned int min_samples_per_frame,
			   unsigned int max_samples_per_frame,
			   unsigned int min_frame_count,
			   unsigned int max_frame_count,
			   unsigned int step_frame_count,
			   unsigned int private_size);
int generator_context_run(struct test_generator *gen, generator_cb_t cb);
void generator_context_destroy(struct test_generator *gen);

#endif
