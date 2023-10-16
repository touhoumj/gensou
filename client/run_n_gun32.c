// Now with support for win32 :^)

#include <Windows.h>
#include <winternl.h>

#include <io.h>
#include <stdbool.h>
#include <stdio.h>

//#define GFL_HAXX

bool exists(char *path)
{
	if(_access_s(path, 0)) {
		char buffer[256];
		strerror_s(buffer, sizeof(buffer), errno);
		printf("_access_s failure: %s. are you sure %s exists?\n", buffer, path);
		return false;
	}
	return true;
}

void error(const char *function)
{
	DWORD error = GetLastError();
	char *buffer = "";
	DWORD count = FormatMessageA(
		FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
		NULL,
		error,
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		buffer,
		0,
		NULL
	);
	if(count) {
		printf("%s failed: 0x%08lx (%s)\n", function, error, buffer);
	} else {
		printf("%s failed: 0x%08lx (unknown error)\n", function, error);
	}
}

#define CALL_WINAPI(api, args, post) \
    if(!api args) {                  \
        error(#api);                 \
        post;                        \
    }

#define CALL_THREAD_WINAPI(api, args) \
    if(api args == (DWORD)-1) {       \
        error(#api);                  \
        goto cleanup;                 \
    }

#define CALL_WINAPI_CREATE(type, name, api, args) \
    type name = api args;                         \
    if(!name) {                                   \
        error(#api);                              \
        goto cleanup;                             \
    }

bool patch(HANDLE hProcess, void *address, size_t length, const void *new, void *old)
{
	DWORD oldprotect;
	CALL_WINAPI(VirtualProtectEx, (hProcess, address, length, PAGE_EXECUTE_READWRITE, &oldprotect), return false)
	CALL_WINAPI(ReadProcessMemory, (hProcess, address, old, length, NULL), return false)
	CALL_WINAPI(WriteProcessMemory, (hProcess, address, new, length, NULL), return false)
	FlushInstructionCache(hProcess, address, length);
	return true;
}

int main(int argc, char *argv[])
{
	if(argc < 3) {
		printf("Usage: %s <exe> <dll> [args...]\n", argv[0]);
		printf("Extra arguments will be forwarded to the process\n");
		return(-1);
	}
	if(!exists(argv[1])) { return(-1); }
	if(!exists(argv[2])) { return(-1); }
	// Parse arguments to create a new array to pass to the created process.
	// Skip first 3 arguments since they're going to be command_name exe_name dll_name.
	size_t length = 0;
	char *args = NULL;
	bool alloc = false;
	if(argc > 3) {
		for(int i = 3; i < argc; ++i) {
			length += strlen(argv[i]) + 2;
		}
		args = malloc(length * sizeof(char));
		if(!args) {
			printf("malloc() failed, size %zu", length * sizeof(char));
			return(-1);
		}
		alloc = true;
		strcpy_s(args, length, "");
		for(int i = 3; i < argc; ++i) {
			int ret = 0;
			ret = strcat_s(args, length, argv[i]);
			if(ret) {
				printf("strcat_s failure: %d\n", ret);
				free(args);
				return(-1);
			}
			ret = strcat_s(args, length, " ");
			if(ret) {
				printf("strcat_s failure: %d\n", ret);
				free(args);
				return(-1);
			}
		}
	}
	printf("invoking %s with arguments %s\n", argv[1], args);
	STARTUPINFOA startupinfo = { 0 };
	PROCESS_INFORMATION processinformation;
	startupinfo.cb = sizeof(startupinfo);
	CALL_WINAPI(CreateProcessA, (argv[1], args, NULL, NULL, FALSE, CREATE_NEW_CONSOLE | CREATE_SUSPENDED, NULL, NULL, &startupinfo, &processinformation), return(-1))
	HANDLE hProcess = processinformation.hProcess;
	HANDLE hThread = processinformation.hThread;
	// XXX: wtf? Is there a better way of acquiring the PEB?
	LONG(WINAPI *NtQueryInformationProcess)
		(HANDLE ProcessHandle,
		 ULONG ProcessInformationClass, PVOID ProcessInformation,
		 ULONG ProcessInformationLength, PULONG ReturnLength) = NULL;
	*(FARPROC *) &NtQueryInformationProcess = GetProcAddress(GetModuleHandleA("ntdll"), "NtQueryInformationProcess");
	PROCESS_BASIC_INFORMATION basicinformation = {0};
	DWORD dwReturnLength = 0;
	NtQueryInformationProcess(hProcess, ProcessBasicInformation, &basicinformation, sizeof(PROCESS_BASIC_INFORMATION), &dwReturnLength);
	PPEB peb = basicinformation.PebBaseAddress;
	if(!peb) {
		printf("failed to acquire PEB from NtQueryInformationProcess\n");
		if(alloc) { free(args); }
		return(-1);
	}
	DWORD_PTR baseaddress = 0;
	CALL_WINAPI(ReadProcessMemory, (hProcess, &peb->Reserved3[1], &baseaddress, sizeof(baseaddress), NULL), goto cleanup)
	printf("base address @ 0x%08lx\n", baseaddress);
	IMAGE_DOS_HEADER dosheader = {0};
	CALL_WINAPI(ReadProcessMemory, (hProcess, (PVOID)baseaddress, &dosheader, sizeof(dosheader), NULL), goto cleanup)
	if(dosheader.e_magic != IMAGE_DOS_SIGNATURE) {
		printf("dos header signature mismatch (expected 0x%04X but got 0x%04X instead)\n", IMAGE_DOS_SIGNATURE, dosheader.e_magic);
		if(alloc) { free(args); }
		goto cleanup;
	}
	IMAGE_NT_HEADERS32 ntheader32 = {0};
	CALL_WINAPI(ReadProcessMemory, (hProcess, (char *)baseaddress + dosheader.e_lfanew, &ntheader32, sizeof(ntheader32), NULL), goto cleanup)
	if(ntheader32.Signature != IMAGE_NT_SIGNATURE) {
		printf("nt header signature mismatch (expected 0x%08X but got 0x%08lX instead)\n", IMAGE_NT_SIGNATURE, ntheader32.Signature);
		if(alloc) { free(args); }
		goto cleanup;
	}
	if(ntheader32.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC) {
		printf("nt optional header signature mismatch (expected 0x%04X but got 0x%04X instead)\n", IMAGE_NT_OPTIONAL_HDR64_MAGIC, ntheader32.OptionalHeader.Magic);
		if(alloc) { free(args); }
		goto cleanup;
	}
	DWORD_PTR entrypoint = baseaddress + ntheader32.OptionalHeader.AddressOfEntryPoint;
	printf("entrypoint @ 0x%08lx\n", entrypoint);
#ifndef GFL_HAXX
	WORD old;
	WORD new = 0xFEEB; // JMP -2
	if(!patch(hProcess, (void *)entrypoint, sizeof(WORD), &new, &old)) {
		printf("failed to write patch to entrypoint\n");
		goto cleanup;
	}
	printf("patched entrypoint (old: %x | new: %x)\n", old, new);
	// For whatever reason GF2_Exilium never hits the actual entrypoint?
	while(1) {
		CALL_THREAD_WINAPI(ResumeThread, (hThread))
		Sleep(100);
		CALL_THREAD_WINAPI(SuspendThread, (hThread))
		CONTEXT context = {0};
		context.ContextFlags = CONTEXT_FULL;
		CALL_WINAPI(GetThreadContext, (hThread, &context), goto cleanup)
		printf("ctx eip: 0x%08lx\n", context.Eip);
		if(context.Eip == entrypoint) { break; }
	}
#endif
	CALL_WINAPI_CREATE(HMODULE, hKernel32, GetModuleHandleA, ("kernel32"))
	CALL_WINAPI_CREATE(LPTHREAD_START_ROUTINE, loadlibrary, (LPTHREAD_START_ROUTINE)GetProcAddress, (hKernel32, "LoadLibraryA"))
	char path[MAX_PATH] = {0};
	CALL_WINAPI_CREATE(DWORD, pathlen, GetFullPathNameA, (argv[2], sizeof(path), path, NULL))
	CALL_WINAPI_CREATE(void *, remotepath, VirtualAllocEx, (hProcess, NULL, pathlen + 1, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE))
	CALL_WINAPI(WriteProcessMemory, (hProcess, remotepath, path, pathlen + 1, NULL), goto cleanup)
	CALL_WINAPI_CREATE(HANDLE, loadlibrarythread, CreateRemoteThread, (hProcess, NULL, 0, loadlibrary, remotepath, 0, NULL))
	WaitForSingleObject(loadlibrarythread, INFINITE);
	if(loadlibrarythread) { CloseHandle(loadlibrarythread); }
	if(remotepath) { VirtualFreeEx(hProcess, remotepath, 0, MEM_RELEASE); }
#ifndef GFL_HAXX
	if(!patch(hProcess, (void *)entrypoint, sizeof(WORD), &old, &new)) {
		printf("failed to erase patch to entrypoint\n");
		goto cleanup;
	}
#endif
	CALL_THREAD_WINAPI(ResumeThread, (hThread))
	if(hProcess) { CloseHandle(hProcess); }
	if(hThread) { CloseHandle(hThread); }
	if(alloc) { free(args); }
	return(0);
	cleanup:
		if(hProcess) {
			TerminateProcess(hProcess, -1);
			CloseHandle(hProcess);
		}
		if(hThread) { CloseHandle(hThread); }
		if(alloc) { free(args); }
		return(-1);
}
