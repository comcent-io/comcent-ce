package main

import (
	"bytes"
	"io"
	"net"
	"sync"
)

type pipeListener struct {
	ch     chan net.Conn
	once   sync.Once
	closed chan struct{}
}

func newPipeListener() *pipeListener {
	return &pipeListener{
		ch:     make(chan net.Conn, 16),
		closed: make(chan struct{}),
	}
}

func (l *pipeListener) Inject(conn net.Conn) {
	select {
	case l.ch <- conn:
	case <-l.closed:
		conn.Close()
	}
}

func (l *pipeListener) Accept() (net.Conn, error) {
	select {
	case conn := <-l.ch:
		return conn, nil
	case <-l.closed:
		return nil, net.ErrClosed
	}
}

func (l *pipeListener) Close() error {
	l.once.Do(func() { close(l.closed) })
	return nil
}

func (l *pipeListener) Addr() net.Addr {
	return &net.TCPAddr{IP: net.IPv4(0, 0, 0, 0), Port: 80}
}

// prefixConn wraps a net.Conn, prepending buffered data before the real connection.
type prefixConn struct {
	net.Conn
	reader io.Reader
}

func newPrefixConn(conn net.Conn, prefix []byte) *prefixConn {
	return &prefixConn{
		Conn:   conn,
		reader: io.MultiReader(bytes.NewReader(prefix), conn),
	}
}

func (c *prefixConn) Read(b []byte) (int, error) {
	return c.reader.Read(b)
}
