package model

// CreateStudentRequest is the body for creating or updating a student.
type CreateStudentRequest struct {
	StudentID     uint   `json:"student_id"` // client-supplied primary key (create only)
	Name          string `json:"name"`
	ProfilePicURL string `json:"profile_pic_url"` // image link; empty = no picture
}

// Student is a row in the students table. Primary key: StudentID.
type Student struct {
	StudentID     uint   `json:"student_id"`
	Name          string `json:"name"`
	ProfilePicURL string `json:"profile_pic_url"` // image link; empty = no picture
}

// SetStudentsRequest is the body of POST /api/users/students: it replaces the
// target user's student roster with StudentIDs.
type SetStudentsRequest struct {
	UserID     *uint  `json:"user_id"` // required: the user whose roster to set
	StudentIDs []uint `json:"student_ids"`
}

// StudentAssignResult is the per-id outcome of a bulk roster set.
type StudentAssignResult struct {
	StudentID uint   `json:"student_id"`
	Status    int    `json:"status"`
	Error     string `json:"error,omitempty"`
}

// SetStudentsResponse is the 207 Multi-Status body for a bulk roster set.
type SetStudentsResponse struct {
	Results []StudentAssignResult `json:"results"`
}
