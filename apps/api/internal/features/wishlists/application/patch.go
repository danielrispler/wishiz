package application

import "encoding/json"

type PatchField[T any] struct {
	Set   bool
	Value T
}

func (f *PatchField[T]) UnmarshalJSON(data []byte) error {
	f.Set = true
	return json.Unmarshal(data, &f.Value)
}
