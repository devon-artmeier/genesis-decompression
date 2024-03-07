; ----------------------------------------------------------------------
; Decompress Enigma tilemap data
; ----------------------------------------------------------------------
; Format details: https://segaretro.org/Enigma_compression
; ----------------------------------------------------------------------
; PARAMETERS:
;	a0.l - Pointer to source tilemap data
;	a1.l - Pointer to destination buffer
;	d0.w - Base tile properties
; ----------------------------------------------------------------------
; RETURNS:
;	a0.l - Pointer to end of source tilemap data
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
; Advance bitstream
; ----------------------------------------------------------------------

ENI_ADVANCE macro
	cmpi.w	#8,d6					; Should we get another byte?
	bhi.s	.NoRead\@				; If not, branch

	move.w	d6,d7					; Get number of bits read past byte
	subq.w	#8,d7
	neg.w	d7
	
	ror.w	d7,d5					; Read another byte
	move.b	(a0)+,d5
	rol.w	d7,d5
	addq.w	#8,d6

.NoRead\@:
	endm

; ----------------------------------------------------------------------
; Get tile flag
; ----------------------------------------------------------------------
; PARAMETERS:
;	bit - Bit ID
;	off - Offset instead of replace
; ----------------------------------------------------------------------

ENI_TILE_FLAG macro bit, off
	add.b	d7,d7					; Is the priority flag set?
	bcc.s	.NotSet\@				; If not, branch
	subq.w	#1,d6					; Does this tile have its priority flag set?
	rol.w	#1,d5
	bcc.s	.NotSet\@				; If not, branch
	if off<>0
		addi.w	#1<<bit,d3			; Offset flag in base tile properties
	else
		ori.w	#1<<bit,d3			; Set flag in base tile properties
	endif

.NotSet\@:
	endm

; ----------------------------------------------------------------------
; Enigma decompression function
; ----------------------------------------------------------------------

EniDec:
	movem.l	d0-d6/a2-a5,-(sp)			; Save registers
	movea.w	d0,a2					; Save base tile properties

	moveq	#0,d4					; Get number of tile bits
	move.b	(a0)+,d4
	move.b	(a0)+,d0				; Get tile flags
	lsl.b	#3,d0
	movea.w	d0,a3
	movea.w	(a0)+,a4				; Get incrementing tile
	adda.w	a2,a4
	movea.w	(a0)+,a5				; Get static tile
	adda.w	a2,a5

	move.w	(a0)+,d5				; Get first word
	moveq	#16,d6

; ----------------------------------------------------------------------

EniDec_GetCode:
	subq.w	#1,d6					; Does the next code involve using an inline tile?
	rol.w	#1,d5
	bcs.s	.InlineTileCode				; If so, branch

	subq.w	#1,d6					; Should we copy the static tile?
	rol.w	#1,d5
	bcs.s	.Mode01					; If so, branch

.Mode00:
	subq.w	#4,d6					; Get copy length
	rol.w	#4,d5
	move.w	d5,d0
	andi.w	#$F,d0
	
.Mode00Copy:
	move.w	a4,(a1)+				; Copy incrementing tile
	addq.w	#1,a4					; Increment
	dbf	d0,.Mode00Copy				; Loop until enough is copied
	bra.s	.NextCode				; Process next code

.Mode01:
	subq.w	#4,d6					; Get copy length
	rol.w	#4,d5
	move.w	d5,d0
	andi.w	#$F,d0
	
.Mode01Copy:
	move.w	a5,(a1)+				; Copy static tile
	dbf	d0,.Mode01Copy				; Loop until enough is copied
	
.NextCode:
	ENI_ADVANCE					; Advance bitstream
	bra.s	EniDec_GetCode				; Process next code

.InlineTileCode:
	subq.w	#2,d6					; Get code
	rol.w	#2,d5
	move.w	d5,d1
	andi.w	#%11,d1
	
	subq.w	#4,d6					; Get copy length
	rol.w	#4,d5
	move.w	d5,d0
	andi.w	#$F,d0
	
	ENI_ADVANCE					; Advance bitstream

	add.w	d1,d1					; Handle code
	jsr	.InlineCodes(pc,d1.w)
	
	bra.s	EniDec_GetCode				; Process next code

; ----------------------------------------------------------------------

.InlineCodes:
	bra.s	EniDec_InlineMode00
	bra.s	EniDec_InlineMode01
	bra.s	EniDec_InlineMode10
	
; ----------------------------------------------------------------------

EniDec_InlineMode11:
	cmpi.w	#$F,d0					; Are we at the end?
	beq.s	EniDec_Done				; If so, branch

.Copy:
	bsr.s	EniDec_GetInlineTile			; Get tile
	move.w	d1,(a1)+				; Store tile
	dbf	d0,.Copy				; Loop until enough is copied
	rts
	
; ----------------------------------------------------------------------

EniDec_Done:
	addq.w	#4,sp					; Discard return address
	
	subq.w	#1,a0					; Discard trailing byte
	cmpi.w	#16,d6					; Are there 2 trailing bytes?
	bne.s	.End					; If not, branch
	subq.w	#1,a0					; If so, discard the other byte
	
.End:
	movem.l	(sp)+,d0-d6/a2-a5			; Restore registers
	rts

; ----------------------------------------------------------------------

EniDec_InlineMode00:
	bsr.s	EniDec_GetInlineTile			; Get tile

.Copy:
	move.w	d1,(a1)+				; Copy tile
	dbf	d0,.Copy				; Loop until enough is copied
	rts
	
; ----------------------------------------------------------------------

EniDec_InlineMode01:
	bsr.s	EniDec_GetInlineTile			; Get tile

.Copy:
	move.w	d1,(a1)+				; Copy tile
	addq.w	#1,d1					; Increment
	dbf	d0,.Copy				; Loop until enough is copied
	rts
	
; ----------------------------------------------------------------------

EniDec_InlineMode10:
	bsr.s	EniDec_GetInlineTile			; Get tile

.Copy:
	move.w	d1,(a1)+				; Copy tile
	subq.w	#1,d1					; Decrement
	dbf	d0,.Copy				; Loop until enough is copied
	rts

; ----------------------------------------------------------------------

EniDec_GetInlineTile:
	move.w	a3,d7					; Get tile flags
	move.w	a2,d3					; Get base tile properties

	ENI_TILE_FLAG 15,0				; Priority
	ENI_TILE_FLAG 14,1				; Palette
	ENI_TILE_FLAG 13,1
	ENI_TILE_FLAG 12,0				; Y flip
	ENI_TILE_FLAG 11,0				; X flip
	
	ENI_ADVANCE					; Advance bitstream

	moveq	#0,d2					; Reset upper bits
	move.w	d4,d1					; Get number of bits in a tile ID
	cmpi.w	#8,d1					; Is it more than 8 bits?
	bls.s	.GetTileID				; If not, branch
	
	rol.w	#8,d5					; Get first 8 bits of tile ID
	move.b	d5,d2
	
	subq.w	#8,d1					; Get remaining number of bits
	lsl.w	d1,d2
	
	move.w	d6,d7					; Get number of bits read past byte
	subi.w	#16,d7
	neg.w	d7
	
	ror.w	d7,d5					; Read another byte
	move.b	(a0)+,d5
	rol.w	d7,d5

.GetTileID:
	sub.w	d1,d6					; Get tile ID bits
	rol.w	d1,d5
	
	move.w	d1,d7					; Apply mask and base tile properties
	add.w	d7,d7
	move.w	d5,d1
	and.w	.Masks-2(pc,d7.w),d1
	or.w	d2,d1
	add.w	d3,d1
	
	ENI_ADVANCE					; Advance bitstream
	rts

; ----------------------------------------------------------------------

.Masks:
	dc.w	%0000000000000001
	dc.w	%0000000000000011
	dc.w	%0000000000000111
	dc.w	%0000000000001111
	dc.w	%0000000000011111
	dc.w	%0000000000111111
	dc.w	%0000000001111111
	dc.w	%0000000011111111
	dc.w	%0000000111111111
	dc.w	%0000001111111111
	dc.w	%0000011111111111
	dc.w	%0000111111111111
	dc.w	%0001111111111111
	dc.w	%0011111111111111
	dc.w	%0111111111111111
	dc.w	%1111111111111111
	
; ----------------------------------------------------------------------