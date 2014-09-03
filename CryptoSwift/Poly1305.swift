//
//  Poly1305.swift
//  CryptoSwift
//
//  Created by Marcin Krzyzanowski on 30/08/14.
//  Copyright (c) 2014 Marcin Krzyzanowski. All rights reserved.
//
//  http://tools.ietf.org/html/draft-agl-tls-chacha20poly1305-04#section-4
//
//  Poly1305 takes a 32-byte, one-time key and a message and produces a 16-byte tag that authenticates the
//  message such that an attacker has a negligible chance of producing a valid tag for an inauthentic message.

import Foundation

public class Poly1305 {
    let blockSize = 16
    private var ctx:Context
    
    private class Context {
        var r            = [Byte](count: 17, repeatedValue: 0)
        var h            = [Byte](count: 17, repeatedValue: 0)
        var pad          = [Byte](count: 17, repeatedValue: 0)
        var buffer       = [Byte](count: 16, repeatedValue: 0)
        
        var final:Byte   = 0
        var leftover:Int = 0
        
        init (_ key: [Byte]) {
            assert(key.count == 32,"Invalid key length");
            if (key.count != 32) {
                return;
            }
            
            for i in 0..<17 {
                h[i] = 0
            }
            
            r[0] = key[0] & 0xff;
            r[1] = key[1] & 0xff;
            r[2] = key[2] & 0xff;
            r[3] = key[3] & 0x0f;
            r[4] = key[4] & 0xfc;
            r[5] = key[5] & 0xff;
            r[6] = key[6] & 0xff;
            r[7] = key[7] & 0x0f;
            r[8] = key[8] & 0xfc;
            r[9] = key[9] & 0xff;
            r[10] = key[10] & 0xff;
            r[11] = key[11] & 0x0f;
            r[12] = key[12] & 0xfc;
            r[13] = key[13] & 0xff;
            r[14] = key[14] & 0xff;
            r[15] = key[15] & 0x0f;
            r[16] = 0
            
            for i in 0..<16 {
                pad[i] = key[i + 16]
            }
            pad[16] = 0
            
            leftover = 0
            final = 0
        }
        
        deinit {
            for i in 0..<buffer.count {
                buffer[i] = 0
            }
            
            for i in 0..<r.count {
                r[i] = 0
                h[i] = 0
                pad[i] = 0
                final = 0
                leftover = 0
            }
        }
    }
    
    class public func withKey(key: [Byte]) -> Poly1305 {
        return Poly1305(key)
    }
    
    private init (_ key: [Byte]) {
        ctx = Context(key)
    }
    
    public func auth(mac:[Byte], message:[Byte]) -> [Byte]? {
        update(ctx, m: message)
        return finish(ctx, mac: mac)
    }
    
    private func add(context:Context, c:[Byte]) -> Bool {
        if (context.h.count != 17 && c.count != 17) {
            return false
        }
        
        var u:UInt16 = 0
        for i in 0..<17 {
            u += UInt16(context.h[i]) + UInt16(c[i])
            context.h[i] = Byte.withValue(u)
            u = u >> 8
        }
        return true
    }
    
    private func squeeze(context:Context, hr:[UInt32]) -> Bool {
        if (context.h.count != 17 && hr.count != 17) {
            return false
        }

        var u:UInt32 = 0

        for i in 0..<16 {
            u += hr[i];
            context.h[i] = Byte.withValue(u) // crash! h[i] = UInt8(u) & 0xff
            u >>= 8;
        }
        
        u += hr[16]
        context.h[16] = Byte.withValue(u) & 0x03
        u >>= 2
        u += (u << 2); /* u *= 5; */
        for i in 0..<16 {
            u += UInt32(context.h[i])
            context.h[i] = Byte.withValue(u) // crash! h[i] = UInt8(u) & 0xff
            u >>= 8
        }
        context.h[16] += Byte.withValue(u);
        
        return true
    }
    
    private func freeze(context:Context) -> Bool {
        assert(context.h.count == 17,"Invalid length")
        if (context.h.count != 17) {
            return false
        }
        
        let minusp:[Byte] = [0x05,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xfc]
        var horig:[Byte] = [Byte](count: 17, repeatedValue: 0)
        
        /* compute h + -p */
        for i in 0..<17 {
            horig[i] = context.h[i]
        }
        
        add(context, c: minusp)
        
        /* select h if h < p, or h + -p if h >= p */
        let bits:[Bit] = (context.h[16] >> 7).bits()
        let invertedBits = bits.map({ (bit) -> Bit in
            return bit.inverted()
        })
        
        let negative = Byte(bits: invertedBits)
        for i in 0..<17 {
            context.h[i] ^= negative & (horig[i] ^ context.h[i]);
        }
        
        return true;
    }
    
    private func blocks(context:Context, m:[Byte], startPos:Int = 0) -> Int {
        var bytes = m.count
        let hibit = context.final ^ 1 // 1 <<128
        var mPos = startPos
        
        while (bytes >= Int(blockSize)) {
            var hr:[UInt32] = [UInt32](count: 17, repeatedValue: 0)
            var u:UInt32 = 0
            var c:[Byte] = [Byte](count: 17, repeatedValue: 0)
            
            /* h += m */
            for i in 0..<16 {
                c[i] = m[mPos + i]
            }
            c[16] = hibit

            add(context, c: c)

            /* h *= r */
            for i in 0..<17 {
                u = 0
                for j in 0...i {
                    u = u + UInt32(UInt16(context.h[j])) * UInt32(context.r[i - j]) // u += (unsigned short)st->h[j] * st->r[i - j];
                }
                for j in (i+1)..<17 {
                    var v:UInt32 = UInt32(UInt16(context.h[j])) * UInt32(context.r[i + 17 - j])  // unsigned long v = (unsigned short)st->h[j] * st->r[i + 17 - j];
                    v = ((v &<< 8) &+ (v &<< 6))
                    u = u &+ v
                }
                hr[i] = u
            }
            
            squeeze(context, hr: hr)

            mPos += blockSize
            bytes -= blockSize
        }
        return mPos
    }
    
    private func finish(context:Context, mac:[Byte]) -> [Byte]? {
        assert(mac.count == 16, "Invalid mac length")
        if (mac.count != 16) {
            return nil
        }
        
        var resultMAC = mac;
        
        /* process the remaining block */
        if (context.leftover > 0) {
            
            var i = context.leftover
            context.buffer[i++] = 1
            for (; i < blockSize; i++) {
                context.buffer[i] = 0
            }
            context.final = 1
            
            blocks(context, m: context.buffer)
        }
        
        
        /* fully reduce h */
        freeze(context)
        
        /* h = (h + pad) % (1 << 128) */
        add(context, c: context.pad)
        for i in 0..<16 {
            resultMAC[i] = context.h[i]
        }
        
        return resultMAC
    }
    
    private func update(context:Context, m:[Byte]) {
        var bytes = m.count
        var mPos = 0
        
        /* handle leftover */
        if (context.leftover > 0) {
            var want = blockSize - context.leftover
            if (want > bytes) {
                want = bytes
            }
            
            for i in 0..<want {
                context.buffer[context.leftover + i] = m[mPos + i]
            }
            
            bytes -= want
            mPos += want
            context.leftover += want
            
            if (context.leftover < blockSize) {
                return
            }
            
            blocks(context, m: context.buffer)
            context.leftover = 0
        }
        
        /* process full blocks */
        if (bytes >= blockSize) {
            var want = bytes & ~(blockSize - 1)
            blocks(context, m: m, startPos: mPos)
            mPos += want
            bytes -= want;
        }
        
        /* store leftover */
        if (bytes > 0) {
            for i in 0..<bytes {
                context.buffer[context.leftover + i] = m[mPos + i]
            }
            
            context.leftover += bytes
        }
    }
}