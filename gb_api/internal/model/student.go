package model

// CreateStudentRequest is the body for creating or updating a student.
type CreateStudentRequest struct {
	Name          string `json:"name"`
	ProfilePicURL string `json:"profile_pic_url"` // image link; empty = no picture
}

// Student is a row in the students table. Primary key: StudentID.
type Student struct {
	StudentID     uint   `json:"student_id"`
	Name          string `json:"name"`
	ProfilePicURL string `json:"profile_pic_url"` // image link; empty = no picture
}
