import { NextResponse } from 'next/server';

export async function POST(request: Request) {
  try {
    const { seconds } = await request.json();
    
    if (!seconds) {
      return NextResponse.json({ error: 'Seconds parameter is required' }, { status: 400 });
    }

    const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL || 'http://127.0.0.1:8545';
    console.log(`[API] Increasing time by ${seconds}s via ${rpcUrl}`);

    // 1. Increase Time
    await fetch(rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [Number(seconds)],
        id: new Date().getTime(),
      }),
    });

    // 2. Mine a block to persist the time change
    await fetch(rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'evm_mine',
        params: [],
        id: new Date().getTime() + 1,
      }),
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error increasing time:', error);
    return NextResponse.json({ error: 'Failed to increase time' }, { status: 500 });
  }
}
