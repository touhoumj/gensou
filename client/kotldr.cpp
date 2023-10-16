// clang++ kotldr.cpp -o kotldr.dll -m32 -shared -ldetours -std=c++17

#include <conio.h>
#include <cstdio>
#include <filesystem>
#include <string>
#include <vector>
#include <Windows.h>

#include "detours.h"

#define log(fmt, ...) printf("%s: " fmt "\n", __FUNCTION__, ##__VA_ARGS__)
#define die(fmt, ...) do { log(fmt, ##__VA_ARGS__); for(;;) {} } while(0)

typedef WINAPI HANDLE (*createfilea_t)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
typedef WINAPI BOOL (*closehandle_t)(HANDLE);
typedef WINAPI BOOL (*readfile_t)(HANDLE, LPVOID, DWORD, LPDWORD, LPOVERLAPPED);

createfilea_t createfilea_orig = CreateFileA;
closehandle_t closehandle_orig = CloseHandle;
readfile_t readfile_orig = ReadFile;

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

std::vector<pack_entry_t> entries;

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
		if(pos > entries_end) {
			/* expensive, but it works */
			for(size_t i = 0; i < entries.size(); ++i) {
				pack_entry_t *target = &entries[i];

				log("reading %s from pack", target->name);
				if(target->start == pos && target->length == nNumberOfBytesToRead) {
					FILE *fp;
					fopen_s(&fp, target->name, "rb");

					if(fp) {
						fseek(fp, 0, SEEK_END);
						size_t fz = ftell(fp);
						fseek(fp, 0, SEEK_CUR);

						if(fz > nNumberOfBytesToRead) {
							/* XXX: This is dangerous, but should work? */
							realloc(lpBuffer, fz);
						}

						*lpNumberOfBytesRead = fread(lpBuffer, 1, fz, fp);
						fclose(fp);

						return TRUE;
					}
					break;
				}
			}
		}
	}

	return readfile_orig(hFile, lpBuffer, nNumberOfBytesToRead, lpNumberOfBytesRead, lpOverlapped);
}

void preflight()
{
	std::string exe_name;
	exe_name.resize(MAX_PATH);

	if(!GetModuleFileNameA(NULL, (LPSTR)exe_name.data(), exe_name.max_size())) {
		die("GetModuleFileNameA failed: %ld", GetLastError());
	}

	pack_name = "./" + std::filesystem::path(exe_name).stem().string() + ".p";

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

	for(uint32_t i = 0; i < header.count; ++i) {
		pack_entry_t entry;
		if(fread(&entry, sizeof(pack_entry_t), 1, fp) != 1) {
			fclose(fp);
			die("failed to read %zu bytes", sizeof(pack_entry_t));
		}

		entries.push_back(entry);
	}

	entries_end = ftell(fp);
	log("entries end at offset 0x%zx", entries_end);

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
