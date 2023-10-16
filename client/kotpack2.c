/* i think there's already a kotpack.* somewhere out there */

// clang kotpack2.c -o kotpack2 -lz
// yes, this code is a mess. i know

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <zlib.h>

#ifdef assert
#undef assert
#endif /* assert */

#define log(fmt, ...) printf(fmt "\n", ##__VA_ARGS__)
#define assert(x) if(!(x)) do { log("assertion '%s' failed (%s:%d)", #x, __FUNCTION__, __LINE__); exit(1); } while(0)

#ifndef _WIN32
#define fopen_s(fp, filename, mode) *(fp) = fopen(filename, mode)
#endif /* _WIN32 */

int main(int argc, char *argv[])
{
	if(argc != 3) {
		log("usage: %s <in.cfg> <out.cfg>", argv[0]);
		return 1;
	}

	FILE *fp = NULL;
	fopen_s(&fp, argv[1], "rb");
	assert(fp);

	fseek(fp, 0, SEEK_END);
	size_t fz = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	void *buffer = NULL;
	assert(buffer = malloc(fz));

	assert(fz == fread(buffer, 1, fz, fp));
	assert(!fclose(fp));

	/* i'm so sorry */
	assert(*(uint32_t *)buffer == __builtin_bswap32(0x44534001));

	uLongf buf_sz = ((uint32_t *)buffer)[1];

	void *buffer2 = NULL;
	assert(buffer2 = malloc(buf_sz));

	assert(uncompress(buffer2, &buf_sz, buffer + 8, fz) == Z_OK);

	fopen_s(&fp, argv[2], "wb");
	assert(fp);

	assert(buf_sz == fwrite(buffer2, 1, buf_sz, fp));
	assert(!fclose(fp));

	free(buffer);
	free(buffer2);

	return 0;
}
