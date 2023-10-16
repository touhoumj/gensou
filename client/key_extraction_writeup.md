messy writeup loosely detailing how all of this was done:

(for context: i was looking at the *updater* binary. the keys/method shouldn't change though)

after poking around random places for a bit i couldn't find any leads, no luck searching for 'decrypt', etc. doesn't help that openssl is statically linked so we'll get a lot of false positives.

it's never a terrible idea to just hope that you get lucky, but you can't expect it to always work :^)

we do have a few leads to try though. there's an existing decryption tool that implies the usage of blowfish, so we should probably start there. if that fails, we can attempt to trace calls to CreateFileA/W, or corrupt the data and see if we can get a crash message.

running 'strings' on the binary (make sure to decompress it with upx -d first!), and grepping for openssl, we get an exact version: `OpenSSL 1.0.1f 6 Jan 2014`

we can pull down a copy that matches this and look around the source tree while exploring the binary in IDA. it's always a good idea to use publicly available sources, because regardless of potential modifications, you'll likely be able to gain some extra information.

looking for xrefs to the string 'blowfish' in ida, we find one:
```c
sub_5196D0("blowfish", 32770, "BF-CBC");
```

lets grep for this value in our openssl source tree and see what we can find. i'll start with the BF-CBC string.

```sh
openssl-1.0.1f % rg "BF-CBC"
# -snip-
crypto\objects\objects.h
504:#define SN_bf_cbc                   "BF-CBC"
# -snip-
```

now that we have a macro name, we can refine our search:

```sh
openssl-1.0.1f % rg SN_bf_cbc
# -snip-
crypto\evp\c_allc.c
140:    EVP_add_cipher_alias(SN_bf_cbc,"BF");
141:    EVP_add_cipher_alias(SN_bf_cbc,"bf");
142:    EVP_add_cipher_alias(SN_bf_cbc,"blowfish");
# -snip-
```

progress!

it's clear that EVP_add_cipher_alias doesn't align with our pseudocode. this function might be a macro, or a wrapper that was inlined.

```sh
openssl-1.0.1f % rg EVP_add_cipher_alias
# -snip-
crypto\evp\evp.h
539:#define EVP_add_cipher_alias(n,alias) \
# -snip-
```

ah, a macro:
```c
#define EVP_add_cipher_alias(n,alias) \
	OBJ_NAME_add((alias),OBJ_NAME_TYPE_CIPHER_METH|OBJ_NAME_ALIAS,(n))
```

this looks exactly like what we're seeing in IDA now. i was too lazy to validate that `(OBJ_NAME_TYPE_CIPHER_METH|OBJ_NAME_ALIAS) == 32770`, but it'll *probably* be fine.

this is fine, but it doesn't actually get us any closer to our desired key. lets take another look at the openssl source and our pseudocode:

```c
/* openssl */
	EVP_add_cipher(EVP_bf_ecb());
	EVP_add_cipher(EVP_bf_cfb());
	EVP_add_cipher(EVP_bf_ofb());
	EVP_add_cipher(EVP_bf_cbc());
	EVP_add_cipher_alias(SN_bf_cbc,"BF");
	EVP_add_cipher_alias(SN_bf_cbc,"bf");
	EVP_add_cipher_alias(SN_bf_cbc,"blowfish");

/* pseudocode */
	v34 = sub_5220D0();
	sub_512D20(v34);
	v35 = sub_5220B0();
	sub_512D20(v35);
	v36 = sub_5220C0();
	sub_512D20(v36);
	v37 = sub_5220A0();
	sub_512D20(v37);
	sub_5196D0("BF", 32770, "BF-CBC");
	sub_5196D0("bf", 32770, "BF-CBC");
	sub_5196D0("blowfish", 32770, "BF-CBC");
```

hex-rays creates an intermediary variable to store the result of each function before invoking what is likely EVP_add_cipher. we can rename some of these functions to make the pseudocode a bit cleaner.

```c
	v34 = EVP_bf_ecb();
	EVP_add_cipher(v34);
	v35 = EVP_bf_cfb();
	EVP_add_cipher(v35);
	v36 = EVP_bf_ofb();
	EVP_add_cipher(v36);
	v37 = EVP_bf_cbc();
	EVP_add_cipher(v37);
	OBJ_NAME_add("BF", 32770, "BF-CBC");
	OBJ_NAME_add("bf", 32770, "BF-CBC");
	OBJ_NAME_add("blowfish", 32770, "BF-CBC");
```

ok. we now have 4 blowfish-related functions and none of them are helpful, unless we know what specifically we're looking for. lets go back to the public decryption tool and see how it works.

```c
/* in the main function */
Blowfish_Init(&cipher, blowfish_key, 56);

/* when writing out files */
Blowfish_Decrypt(&cipher, &L, &R);
```

looks... simple enough. the state is initialized with a 56 byte key, and it's later used for decryption. what does the openssl api look like?

```c
#include <openssl/blowfish.h>

 void BF_set_key(BF_KEY *key, int len, const unsigned char *data);

 void BF_ecb_encrypt(const unsigned char *in, unsigned char *out,
         BF_KEY *key, int enc);
 void BF_cbc_encrypt(const unsigned char *in, unsigned char *out,
         long length, BF_KEY *schedule, unsigned char *ivec, int enc);
 void BF_cfb64_encrypt(const unsigned char *in, unsigned char *out,
         long length, BF_KEY *schedule, unsigned char *ivec, int *num,
         int enc);
 void BF_ofb64_encrypt(const unsigned char *in, unsigned char *out,
         long length, BF_KEY *schedule, unsigned char *ivec, int *num);
 const char *BF_options(void);

 void BF_encrypt(BF_LONG *data,const BF_KEY *key);
 void BF_decrypt(BF_LONG *data,const BF_KEY *key);
```

the most interesting function here is 'BF_set_key'. if we can find it, we're set.

lets try and trace a path from one of the functions we know of and see if we can locate this function.

i chose to start with `EVP_bf_ecb`. we know this function returns a pointer to a `EVP_CIPHER`. 
```c
/* snipped from crypto/evp/evp.h */

struct evp_cipher_st
	{
	int nid;
	int block_size;
	int key_len;		/* Default value for variable length ciphers */
	int iv_len;
	unsigned long flags;	/* Various flags */
	int (*init)(EVP_CIPHER_CTX *ctx, const unsigned char *key,
		    const unsigned char *iv, int enc);	/* init key */
	int (*do_cipher)(EVP_CIPHER_CTX *ctx, unsigned char *out,
			 const unsigned char *in, size_t inl);/* encrypt/decrypt data */
	int (*cleanup)(EVP_CIPHER_CTX *); /* cleanup ctx */
	int ctx_size;		/* how big ctx->cipher_data needs to be */
	int (*set_asn1_parameters)(EVP_CIPHER_CTX *, ASN1_TYPE *); /* Populate a ASN1_TYPE with parameters */
	int (*get_asn1_parameters)(EVP_CIPHER_CTX *, ASN1_TYPE *); /* Get parameters from a ASN1_TYPE */
	int (*ctrl)(EVP_CIPHER_CTX *, int type, int arg, void *ptr); /* Miscellaneous operations */
	void *app_data;		/* Application data */
	} /* EVP_CIPHER */;
```

while this struct name isn't exactly what we expect, the comment at the end has the same name as the return type. lets quickly import this into IDA and see if we can get anything useful. we can stub out any structs we haven't implemented with 'void'

(update: this is typedef'd to EVP_CIPHER in crypto/ossl_typ.h)

```
.rdata:006BB8C0 stru_6BB8C0     evp_cipher_st <5Ch, 8, 10h, 0, 9, offset sub_5220E0, \
.rdata:006BB8C0                                         ; DATA XREF: EVP_bf_ecb↑o
.rdata:006BB8C0                                offset sub_521FC0, 0, 1048h, offset sub_51AE70, \
.rdata:006BB8C0                                offset sub_51AE00, 0, 0>
```

success? init is sub_5220E0, do_cipher is sub_521FC0, and cleanup is null.
we still don't really know what these functions do though, or if they're even useful.

lets start with the do_cipher function. realistically, this probably ends up invoking the BF_encrypt routine at some point.

```c
int __cdecl sub_521FC0(int a1, int a2, int a3, unsigned int a4)
{
  int v4; // eax
  unsigned int v5; // edi
  int v6; // esi
  unsigned int v7; // ebx
  unsigned int v9; // [esp+14h] [ebp+10h]

  v4 = a1;
  v5 = *(_DWORD *)(*(_DWORD *)a1 + 4);
  if ( a4 >= v5 )
  {
    v9 = a4 - v5;
    v6 = a3;
    v7 = 0;
    while ( 1 )
    {
      sub_538870(v6, v6 + a2 - a3, *(_DWORD *)(v4 + 96), *(_DWORD *)(v4 + 8));
      v7 += v5;
      v6 += v5;
      if ( v7 > v9 )
        break;
      v4 = a1;
    }
  }
  return 1;
}
```

we can see a single function call that takes 4 parameters. rather promising.
```c
_BYTE *__cdecl sub_538870(int a1, _BYTE *a2, int a3, int a4)
{
  int v4; // edx
  unsigned int v5; // ecx
  _BYTE *result; // eax
  int v7; // ecx
  unsigned int v8; // [esp+0h] [ebp-8h] BYREF
  int v9; // [esp+4h] [ebp-4h]

  v4 = *(unsigned __int8 *)(a1 + 5);
  v8 = _byteswap_ulong(*(_DWORD *)a1);
  v9 = (v4 << 16) | (*(unsigned __int8 *)(a1 + 4) << 24) | *(unsigned __int8 *)(a1 + 7) | (*(unsigned __int8 *)(a1 + 6) << 8);
  if ( a4 )
    sub_537950(&v8, a3);
  else
    sub_537D80(&v8, a3);
  v5 = v8;
  result = a2;
  *a2 = HIBYTE(v8);
  a2[1] = BYTE2(v5);
  a2[2] = BYTE1(v5);
  a2[3] = v5;
  v7 = v9;
  a2[4] = HIBYTE(v9);
  a2[5] = BYTE2(v7);
  a2[6] = BYTE1(v7);
  a2[7] = v7;
  return result;
}
```

```c
void BF_ecb_encrypt(const unsigned char *in, unsigned char *out,
	     const BF_KEY *key, int encrypt)
	{
	BF_LONG l,d[2];

	n2l(in,l); d[0]=l;
	n2l(in,l); d[1]=l;
	if (encrypt)
		BF_encrypt(d,key);
	else
		BF_decrypt(d,key);
	l=d[0]; l2n(l,out);
	l=d[1]; l2n(l,out);
	l=d[0]=d[1]=0;
	}
```

ignoring compiler optimizations, we can see some kind of pattern here. the 4 parameters appear to be the same, and we can see the check for encrypt (a4) along with two different functions being used.

unfortunately, our luck runs out here. there's 2 other xrefs for BF_decrypt, and neither of them are within the game code. they both appear to be related to some other openssl functions.

time to step back and look at the init function. i originally ignored this because it only had two function calls and the actual encryption routines seemed more interesting, but looking back i might have made a mistake.

```c
int __cdecl sub_5220E0(int a1, int a2)
{
  int v2; // eax

  v2 = sub_51AD70(a1);
  sub_538B30(*(void **)(a1 + 96), v2, a2);
  return 1;
}
```

the call to `sub_538B30` is very interesting. this is the same layout as `BF_set_key`. looking closer:
```c
  memmove_0(a1, &unk_6C0E70, 0x1048u);
  v4 = a2;
  if ( a2 > 72 )
    v4 = 72;
  v5 = a3;
  v6 = (unsigned int)&a3[v4];
  v7 = a1 + 8;
  v47 = 6;
  /* snip */
    for ( i = 0; i < 18; i += 2 )
  {
    sub_537950(&v45, a1);
    v41 = v46;
    *(_DWORD *)&a1[4 * i] = v45;
    *(_DWORD *)&a1[4 * i + 4] = v41;
  }
  for ( j = 0; j < 1024; j += 2 )
  {
    result = sub_537950(&v45, a1);
    v44 = v46;
    *(_DWORD *)&a1[4 * j + 72] = v45;
    *(_DWORD *)&a1[4 * j + 76] = v44;
  }
```

```c
	int i;
	BF_LONG *p,ri,in[2];
	const unsigned char *d,*end;


	memcpy(key,&bf_init,sizeof(BF_KEY));
	p=key->P;

	if (len > ((BF_ROUNDS+2)*4)) len=(BF_ROUNDS+2)*4;

	d=data;
	end= &(data[len]);
	/* snip */
	in[0]=0L;
	in[1]=0L;
	for (i=0; i<(BF_ROUNDS+2); i+=2)
		{
		BF_encrypt(in,key);
		p[i  ]=in[0];
		p[i+1]=in[1];
		}

	p=key->S;
	for (i=0; i<4*256; i+=2)
		{
		BF_encrypt(in,key);
		p[i  ]=in[0];
		p[i+1]=in[1];
		}
```

i snipped out some stuff because it was too long, but it's clear that these are likely the same function. additionally, the same BF_encrypt that we discovered earlier is (re)used.

so, the final step. we need to actually get our key. normally i'd write some kind of cursed detour that hooks this function and prints the output, but i've finally learned how to use a debugger (please clap), so we're going to do this in a more civilized manner.

load the binary into x32dbg, and breakpoint 0x538B30 (i also breakpointed 0x538C96 for good measure).

...and the breakpoint never hit. that's *lovely*.

lets try this again with the game binary (0x682310, 0x682476) and see if we have more luck there.
...the breakpoint still isn't hit.

whatever, maybe the block *is* hardcoded and we can just breakpoint the actual decryption routine instead. (0x681560, 0x68198B)

no dice there either - lets take a step back and try something else, then.

api monitor is a wonderful tool that saves you the time and effort of writing hooks for every win32 function (i had to use context switch to avoid crashes and only monitored CreateFileA/W for now, but this was quite useful!)

we can now see where CreateFileA is invoked - this location seems consistent across calls: IMAGEBASE + 0x005ef07b

```c
      ReadFile(FileA, Buffer, 8u, &NumberOfBytesRead, 0);
      if ( Buffer[0] == 'P'
        && Buffer[1] == 'A'
        && Buffer[2] == 'C'
        && Buffer[3] == 'K'
        && (unsigned __int8)sub_5EE690(FileA, (int)v22, (int)&lDistanceToMove, (int)&Size, (int)&NumberOfBytesRead) )
      {
        SetFilePointer(FileA, lDistanceToMove, 0, 0);
        v6 = (DWORD *)v17;
        v11 = Size;
        *(_DWORD *)v17 = Size;
        v7 = (void *)sub_5EF7E0(v11, 0xFFFF, (int)"..\\Source\\LunaFile.cpp", 446);
        *a3 = v7;
        if ( v7 )
```

oh hey, there's that 'PACK' magic. wish IDA had detected that as a string, but it makes sense that it didn't. i also forgot that ReadFile() existed, oops.

further down, there's also a call to `sub_5EE150`, which has this check:
```c
  if ( *(_BYTE *)*a2 != 'L' || v3[1] != 'Z' || v3[2] != 'S' || v3[3] != 'S' )
    return 0;
```

so this is the LZSS check. from what i've seen in the existing decryption repository, this doesn't actually matter if the files are encrypted. nonetheless useful to note down, since it appears this magic is ignored entirely.

we additionally have this call:
```c
if ( (unsigned __int8)sub_5F3170((int)v6, v7) )
```

v6 seems to be a copy of our input buffer, and v7 seems to be a newly allocated one. following this, we reach another LZSS check:
```c
char __cdecl sub_5F31E0(int a1, void *a2)
{
  size_t v2; // ebx
  int v3; // esi
  char *v4; // edi
  char v5; // bl
  char v7[8]; // [esp+14h] [ebp-14h] BYREF
  int v8; // [esp+24h] [ebp-4h]

  sub_6134F0(v7);
  v8 = 0;
  memset(&unk_AAD52C, 0, 0x100Fu);
  if ( *(_BYTE *)a1 == 'L' && *(_BYTE *)(a1 + 1) == 'Z' && *(_BYTE *)(a1 + 2) == 'S' && *(_BYTE *)(a1 + 3) == 'S' )
  {
    v2 = *(_DWORD *)(a1 + 4);
    sub_614AD0(&unk_AAE540, dword_AAE53C);
    v3 = sub_614A90(v2);
    v4 = sub_5EF450(v3, 0xFFFF, "..\\Source\\LunaLzss.cpp", 541);
    sub_6147D0(a1 + 8, v4, v3);
    memmove_0(a2, v4, v2);
    sub_5EFA30(v4);
    v5 = 1;
  }
  else
  {
    v5 = 0;
  }
  v8 = -1;
  sub_613530(v7);
  return v5;
}
```

at first glance, this routine is rather uninteresting. we have a reference to 'LunaLzss.cpp', a memcpy, and some kind of flag that's set based on whether or not the file had the expected LZSS magic. a brief glance reveals more though:
```c
int __thiscall sub_4CB1D0(_DWORD *this, int a2, int a3)
{
  int result; // eax
  int v4; // [esp+8h] [ebp-18h] BYREF
  int v5; // [esp+Ch] [ebp-14h] BYREF
  int v6; // [esp+10h] [ebp-10h]
  _DWORD *v7; // [esp+14h] [ebp-Ch]
  int j; // [esp+18h] [ebp-8h]
  int i; // [esp+1Ch] [ebp-4h]

  v7 = this;
  for ( i = 0; i < 18; ++i )
  {
    *(_DWORD *)(*v7 + 4 * i) = dword_77D748[i];
    result = i + 1;
  }
  for ( i = 0; i < 4; ++i )
  {
    for ( j = 0; j < 256; ++j )
    {
      *(_DWORD *)(v7[1] + (i << 10) + 4 * j) = dword_77D790[256 * i + j];
      result = j + 1;
    }
  }
  j = 0;
  for ( i = 0; i < 18; ++i )
  {
    v6 = 0;
    v6 = *(unsigned __int8 *)(a2 + (j + 3) % a3) | (*(unsigned __int8 *)(a2 + (j + 2) % a3) << 8) | (*(unsigned __int8 *)(a2 + (j + 1) % a3) << 16) | (*(unsigned __int8 *)(j + a2) << 24);
    *(_DWORD *)(*v7 + 4 * i) ^= v6;
    result = (j + 4) / a3;
    j = (j + 4) % a3;
  }
  v5 = 0;
  v4 = 0;
  for ( i = 0; i < 18; i += 2 )
  {
    sub_4CA5A0(&v5, &v4);
    *(_DWORD *)(*v7 + 4 * i) = v5;
    *(_DWORD *)(*v7 + 4 * i + 4) = v4;
    result = i + 2;
  }
  for ( i = 0; i < 4; ++i )
  {
    for ( j = 0; j < 256; j += 2 )
    {
      sub_4CA5A0(&v5, &v4);
      *(_DWORD *)(v7[1] + (i << 10) + 4 * j) = v5;
      *(_DWORD *)(v7[1] + (i << 10) + 4 * j + 4) = v4;
      result = j + 2;
    }
  }
  return result;
}
```

at this point, i've stared at this god awful code for so long that i've become uncomfortably familiar with how the BF keys are initialized:
```c
  for ( i = 0; i < 18; ++i )
  {
    *(_DWORD *)(*v7 + 4 * i) = dword_77D748[i];
    result = i + 1;
  }
  for ( i = 0; i < 4; ++i )
  {
    for ( j = 0; j < 256; ++j )
    {
      *(_DWORD *)(v7[1] + (i << 10) + 4 * j) = dword_77D790[256 * i + j];
      result = j + 1;
    }
  }
```

this pattern here looks awfully familiar to
```c
	for (i=0; i<(BF_ROUNDS+2); i+=2)
		{
		BF_encrypt(in,key);
		p[i  ]=in[0];
		p[i+1]=in[1];
		}

	p=key->S;
	for (i=0; i<4*256; i+=2)
		{
		BF_encrypt(in,key);
		p[i  ]=in[0];
		p[i+1]=in[1];
		}
	}
```

given we're passing a pointer and a dword, we can imagine the pointer is the key blob that we actually want.
tracing xrefs, we find it *assigned* in a function here:
```c
void *__cdecl sub_5F31C0(void *Src, int Size)
{
  void *result; // eax

  result = memmove_0(&unk_AAE540, Src, Size);
  dword_AAE53C = Size;
  return result;
}
```

thankfully, this only has a single call site:
```c
sub_5F31C0(&unk_9B2388, 56);
```

at this point, we have enough to safely assume this is the desired key blob. it's only a matter of specifying that it's an array, and exporting the data in ida.

epilogue:
an important part of reversing is the ability to identify patterns. realistically, most samples you're going to be working with were written by people with minimal obfuscation in mind. they likely wanted to *deter* others, not spend 4+ years gaining a PhD in cryptography.

aside from that, it's always good to know your target system. remembering that api monitor existed would have saved me a decent amount of time. another trick i could have (ab)used is something i like to refer to as 'buffer trapping'. it's an awful hack, but you change the permissions on a chunk of a buffer to be PAGE_NOACCESS and install an exception handler so you can figure out exactly where said chunk was accessed. does involve a bit of manual work and scaffolding, but it tends to work well as a last ditch effort.

please excuse my awful writing and any typos, i tried my best <3

(i hope this was interesting, at the very least)
