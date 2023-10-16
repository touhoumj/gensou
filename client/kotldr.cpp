// clang++ kotldr.cpp -o kotldr.dll -m32 -shared -ldetours -std=c++17

#include <conio.h>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>
#include <Windows.h>

#include "blowfish.h"
#include "detours.h"
#include "thmj4n.h"

#define log(fmt, ...) printf("%s: " fmt "\n", __FUNCTION__, ##__VA_ARGS__)
#define die(fmt, ...) do { log(fmt, ##__VA_ARGS__); _getch(); exit(1); } while(0)

typedef WINAPI HANDLE (*createfilea_t)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
typedef WINAPI BOOL (*closehandle_t)(HANDLE);
typedef WINAPI BOOL (*readfile_t)(HANDLE, LPVOID, DWORD, LPDWORD, LPOVERLAPPED);

createfilea_t createfilea_orig = CreateFileA;
closehandle_t closehandle_orig = CloseHandle;
readfile_t readfile_orig = ReadFile;

std::string stem_name = "";
std::string pack_name = "";
HANDLE pack_file = NULL;

typedef struct {
	uint32_t magic;
	uint32_t count;
} __attribute__((packed)) pack_header_t;

typedef struct {
	char name[64];
	uint32_t crc32_name;
	uint32_t crc32_data;

	uint32_t start;
	uint32_t length;
} __attribute__((packed)) pack_entry_t;

typedef struct {
	pack_header_t header;
	pack_entry_t entries[];
} __attribute__((packed)) pack_t;

typedef struct {
	char name[64];
	uint32_t start;

	uint32_t old_length;
	uint32_t new_length;

	std::vector<uint8_t> data;
} __attribute__((packed)) patch_t;

typedef struct {
	uint32_t magic;
	uint32_t size;
} __attribute__((packed)) patch_header_t;

std::vector<patch_t> patches;

pack_t *fake_pack = NULL;
size_t entries_end = 0;

template<typename T>
void hook(T *original, T detour, const char *name)
{
	LONG err = 0;
	if((err = DetourTransactionBegin()) != NO_ERROR) {
		die("DetourTransactionBegin() failed: %ld", err);
	}

	if((err = DetourUpdateThread(GetCurrentThread())) != NO_ERROR) {
		die("DetourUpdateThread() failed: %ld", err);
	}

	if((err = DetourAttach((PVOID *)original, (PVOID)detour)) != NO_ERROR) {
		die("DetourAttach() failed: %ld", err);
	}

	if((err = DetourTransactionCommit()) != NO_ERROR) {
		die("DetourTransactionCommit() failed: %ld", err);
	}

	log("hooked %s (0x%p -> 0x%p)", name, original, detour);
}

WINAPI HANDLE createfilea_hook(LPCSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile)
{
	if(!_stricmp(pack_name.c_str(), lpFileName)) {
		if(!pack_file) {
			pack_file = createfilea_orig(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
		}

		return pack_file;
	}

	return createfilea_orig(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
}

WINAPI BOOL closehandle_hook(HANDLE hObject)
{
	if(pack_file == hObject) {
		pack_file = NULL;
	}

	return closehandle_orig(hObject);
}

WINAPI BOOL readfile_hook(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, LPDWORD lpNumberOfBytesRead, LPOVERLAPPED lpOverlapped)
{
	if(hFile == pack_file) {
		/* bleh. */
		LONG pos = SetFilePointer(hFile, 0, NULL, FILE_CURRENT);
		if(pos <= entries_end && nNumberOfBytesToRead == sizeof(pack_entry_t)) {
			memcpy(lpBuffer, (char *)fake_pack + pos, nNumberOfBytesToRead);
			*lpNumberOfBytesRead = nNumberOfBytesToRead;
			SetFilePointer(hFile, nNumberOfBytesToRead, NULL, FILE_CURRENT);
			return TRUE;
		} else {
			/* expensive, but it works */
			for(size_t i = 0; i < patches.size(); ++i) {
				patch_t *target = &patches[i];

				if(target->start == pos && target->new_length == nNumberOfBytesToRead) {
					memcpy(lpBuffer, target->data.data(), nNumberOfBytesToRead);
					*lpNumberOfBytesRead = nNumberOfBytesToRead;
					SetFilePointer(hFile, target->old_length, NULL, FILE_CURRENT); // XXX: Is this needed?
					return TRUE;
				}
			}
		}
	}

	return readfile_orig(hFile, lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesRead, lpOverlapped);
}

uint32_t crc32(unsigned char *data, int size)
{
	uint32_t r = ~0;
	unsigned char *end = data + size;

	while(data < end)
	{
		r ^= *data++;

		for(int i = 0; i < 8; i++)
		{
			uint32_t t = ~((r & 1) - 1); r = (r>>1) ^ (0xEDB88320 & t);
		}
	}

	return ~r;
}

void encrypt(unsigned char *buffer, size_t *size)
{
	BLOWFISH_CTX ctx;
	Blowfish_Init(&ctx, thmj4n_key, sizeof(thmj4n_key));

	*size = (*size + 7) & ~7;
	if(!realloc(buffer, *size)) {
		die("failed to grow buffer!");
	}

	size_t half_block = sizeof(unsigned long);
	for(int i = 0; i < *size; i += (2 * half_block)) {
		unsigned long L, R;

		memcpy(&L, &buffer[i], half_block);
		memcpy(&R, &buffer[i + half_block], half_block);
		Blowfish_Encrypt(&ctx, &L, &R);
		memcpy(&buffer[i], &L, half_block);
		memcpy(&buffer[i + half_block], &R, half_block);
	}
}

void find_override(pack_entry_t *target)
{
	char path[MAX_PATH];
	snprintf(path, MAX_PATH - 1, "%s/%s", stem_name.c_str(), target->name);

	FILE *fp;
	fopen_s(&fp, path, "rb");
	if(fp) {
		log("found acceptable override: %s", path);
		
		fseek(fp, 0, SEEK_END);
		size_t fz = ftell(fp);
		fseek(fp, 0, SEEK_SET);

		/* dummy header */
		patch_header_t header;
		header.magic = *(uint32_t *)"LZSS";
		header.size = fz;

		/* construct patch */
		patch_t patch;
		memcpy(&patch.name, target->name, sizeof(target->name));
		patch.start = target->start;
		patch.old_length = target->length;
		patch.data.insert(patch.data.end(), (uint8_t *)&header, (uint8_t *)&header + sizeof(patch_header_t));

		/* blowfish */
		unsigned char *buffer = (unsigned char *)malloc(fz);
		if(fread(buffer, 1, fz, fp) != fz) {
			die("failed to read override");
		}
		fclose(fp);
		encrypt(buffer, &fz);

		/* append to patch */
		patch.data.insert(patch.data.end(), buffer, buffer + fz);

		patch.new_length = target->length = patch.data.size();
		log("adjusted target length: %u -> %u", patch.old_length, patch.new_length);

		uint32_t old_crc = target->crc32_data;
		target->crc32_data = crc32(patch.data.data(), patch.data.size());
		log("adjusted target crc32: 0x%08x -> 0x%08x", old_crc, target->crc32_data);

		patches.push_back(patch);
	}
}

void preflight()
{
	char exe_name[MAX_PATH];
	if(!GetModuleFileNameA(NULL, exe_name, MAX_PATH)) {
		die("GetModuleFileNameA failed: %ld", GetLastError());
	}

	stem_name = std::filesystem::path(exe_name).stem().string();
	pack_name = "./" + stem_name + ".p";

	/* parse pack */
	log("parsing pack file %s", pack_name.c_str());

	FILE *fp;
	fopen_s(&fp, pack_name.c_str(), "rb");

	if(!fp) {
		die("failed to open %s for reading", pack_name.c_str());
	}

	fseek(fp, 0, SEEK_END);
	size_t fz = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	if(fz < sizeof(pack_header_t)) {
		die("bad file size: %zu", fz);
	}

	pack_header_t header;
	if(fread(&header, sizeof(pack_header_t), 1, fp) != 1) {
		fclose(fp);
		die("failed to read %zu bytes", sizeof(pack_header_t));
	}

	if(memcmp(&header.magic, "PACK", sizeof(header.magic))) {
		fclose(fp);
		die("bad pack magic: 0x%04x", header.magic);
	}

	size_t entries_size = header.count * sizeof(pack_entry_t);
	fake_pack = (pack_t *)malloc(sizeof(pack_t) + entries_size);
	if(!fake_pack) {
		die("failed to allocate fake pack header");
	}

	fake_pack->header = header;
	for(uint32_t i = 0; i < header.count; ++i) {
		pack_entry_t *target = &fake_pack->entries[i];

		if(fread(target, sizeof(pack_entry_t), 1, fp) != 1) {
			fclose(fp);
			die("failed to read %zu bytes", sizeof(pack_entry_t));
		}

		find_override(target);
	}

	entries_end = ftell(fp);
	log("entries end at offset 0x%zx", entries_end);
	log("loaded %zu patch(es)", patches.size());

	fclose(fp);
}

void install_hooks()
{
	hook<createfilea_t>(&createfilea_orig, createfilea_hook, "CreateFileA");
	hook<closehandle_t>(&closehandle_orig, closehandle_hook, "CloseHandle");
	hook<readfile_t>(&readfile_orig, readfile_hook, "ReadFile");
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
	switch(fdwReason) {
		case DLL_PROCESS_ATTACH: {
			AllocConsole();
			freopen_s((FILE **)stdout, "CONOUT$", "w", stdout);
			preflight();
			install_hooks();
			break;
		}

		case DLL_PROCESS_DETACH: {
			FreeConsole();
			break;
		}
	}

	return TRUE;
}
