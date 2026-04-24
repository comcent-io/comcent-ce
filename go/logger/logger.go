package logger

import (
	"os"
	"time"

	"github.com/comcent-io/sip-test-tools/config"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func SetUpLogger() {
	cfg := config.GetConfig()

	lev, err := zerolog.ParseLevel(cfg.LogLevel)
	if err != nil || lev == zerolog.NoLevel {
		lev = zerolog.InfoLevel
	}

	zerolog.TimeFieldFormat = zerolog.TimeFormatUnixMicro

	env := cfg.Env

	if env == "dev" {
		log.Logger = zerolog.New(zerolog.ConsoleWriter{
			Out:        os.Stdout,
			TimeFormat: time.StampMicro,
		}).With().Timestamp().Str("env", env).Logger().Level(lev)
	} else {
		log.Logger = zerolog.New(os.Stdout).
			With().Timestamp().Str("env", env).Logger().Level(lev)
	}
}
