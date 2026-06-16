package model

// MediaUploadResponse is returned after a successful image or audio upload. URL
// is the path the stored file can be fetched from (served by nginx from the
// upload volume).
type MediaUploadResponse struct {
	Filename string `json:"filename"`
	URL      string `json:"url"`
}
