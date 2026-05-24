from uuid import UUID

from pydantic import BaseModel, EmailStr


class RegisterIn(BaseModel):
    email: EmailStr


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: UUID
    email: EmailStr

    model_config = {"from_attributes": True}
