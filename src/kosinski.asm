; ----------------------------------------------------------------------
; Decompress Kosinski data
; ----------------------------------------------------------------------
; Format details: https://segaretro.org/Kosinski_compression
; ----------------------------------------------------------------------
; PARAMETERS:
;	a0.l - Pointer to source data
;	a1.l - Pointer to destination buffer
; ----------------------------------------------------------------------
; RETURNS:
;	a0.l - Pointer to end of source data
;	a1.l - Pointer to end of destination buffer
; ----------------------------------------------------------------------
; Copyright (c) 2024 Devon Artmeier
;
; Permission to use, copy, modify, and/or distribute this software
; for any purpose with or without fee is hereby granted.
;
; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
; WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIE
; WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
; AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
; DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
; PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER 
; TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
; PERFORMANCE OF THIS SOFTWARE.
; ----------------------------------------------------------------------

; ----------------------------------------------------------------------
; Read descriptor field
; ----------------------------------------------------------------------

KOS_READ_DESC macro
	move.b	(a0)+,1(sp)				; Read from data stream
	move.b	(a0)+,(sp)
	move.w	(sp),d1
	moveq	#16-1,d0				; 16 bits to process
	endm
	
; ----------------------------------------------------------------------
; Go to next bit in descriptor field
; ----------------------------------------------------------------------

KOS_NEXT_BIT macro
	dbf	d0,.NoNewDesc				; Decrement bits left to process
	KOS_READ_DESC					; If we need to read another descriptor field, read it

.NoNewDesc:
	endm

; ----------------------------------------------------------------------
; Kosinski decompression function
; ----------------------------------------------------------------------

KosDec:
	movem.l	d0-d4/a2,-(sp)				; Save registers
	subq.w	#2,sp					; Allocate buffer for endian conversion
	
	KOS_READ_DESC					; Read first descriptor field

; ----------------------------------------------------------------------

KosDec_GetCode:
	lsr.w	#1,d1					; Get code
	bcc.s	KosDec_Code0x				; If it's 0, branch

; ----------------------------------------------------------------------

KosDec_Code1:
	KOS_NEXT_BIT					; Advance descriptor field

	move.b	(a0)+,(a1)+				; Copy uncompressed byte
	bra.s	KosDec_GetCode				; Process next code

; ----------------------------------------------------------------------

KosDec_Code0x:
	KOS_NEXT_BIT					; Advance descriptor field

	moveq	#$FFFFFFFF,d2				; Copy offsets are always negative
	moveq	#0,d3					; Reset copy counter

	lsr.w	#1,d1					; Get subcode
	bcs.s	KosDec_Code01				; If the full code is 01, branch

; ----------------------------------------------------------------------

KosDec_Code00:
	KOS_NEXT_BIT					; Advance descriptor field

	lsr.w	#1,d1					; Get number of bytes to copy
	addx.w	d3,d3
	KOS_NEXT_BIT
	lsr.w	#1,d1
	addx.w	d3,d3
	KOS_NEXT_BIT

	move.b	(a0)+,d2				; Get copy offset

; ----------------------------------------------------------------------

KosDec_Copy:
	lea	(a1,d2.w),a2				; Get copy address
	move.b	(a2)+,(a1)+				; Copy a byte

.Copy:
	move.b	(a2)+,(a1)+				; Copy a byte
	dbf	d3,.Copy				; Loop until bytes are copied

	bra.w	KosDec_GetCode				; Process next code

; ----------------------------------------------------------------------

KosDec_Code01:
	KOS_NEXT_BIT					; Advance descriptor field

	move.b	(a0)+,d4				; Get copy offset
	move.b	(a0)+,d3
	move.b	d3,d2
	lsl.w	#5,d2
	move.b	d4,d2

	andi.b	#7,d3					; Get 3-bit copy count
	bne.s	KosDec_Copy				; If this is a 3-bit copy count, branch

	move.b	(a0)+,d3				; Get 8-bit copy count
	beq.s	.End					; If it's 0, we are done decompressing
	subq.b	#1,d3					; Is it 1?
	bne.s	KosDec_Copy				; If not, start copying
	
	bra.w	KosDec_GetCode				; Process next code

.End:
	addq.w	#2,sp					; Free endian conversion buffer
	movem.l	(sp)+,d0-d4/a2				; Restore registers
	rts
	
; ----------------------------------------------------------------------
