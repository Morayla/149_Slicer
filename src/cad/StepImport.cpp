// Native STEP tessellation boundary. OCCT is linked dynamically; no Python,
// FreeCAD installation or scripting engine participates in importing a file.
#include <STEPControl_Reader.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <TopoDS.hxx>
#include <TopExp_Explorer.hxx>
#include <Poly_Triangulation.hxx>
#include <Interface_Static.hxx>
#include <Standard_Failure.hxx>
#include <fstream>
#include <iostream>
#include <vector>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>

static void write32(std::ostream& out, uint32_t value) {
    const char bytes[] = {char(value),char(value>>8),char(value>>16),char(value>>24)};
    out.write(bytes,4);
}
static void writeFloat(std::ostream& out, float value) {
    uint32_t bits;std::memcpy(&bits,&value,4);write32(out,bits);
}
int main(int argc,char** argv) {
    if(argc!=4){std::cerr<<"Usage: 149-step input.step output.stl tolerance_mm\n";return 2;}
    try {
        char* end=nullptr;const double tolerance=std::strtod(argv[3],&end);
        if(!end || *end || !std::isfinite(tolerance) || tolerance<.02 || tolerance>1)
            throw std::runtime_error("STEP tolerance must be 0.02–1 mm.");
        STEPControl_Reader reader;
        Interface_Static::SetCVal("xstep.cascade.unit","MM");
        if(reader.ReadFile(argv[1])!=IFSelect_RetDone || reader.TransferRoots()==0)
            throw std::runtime_error("STEP does not contain a transferable shape.");
        const TopoDS_Shape shape=reader.OneShape();
        if(shape.IsNull())throw std::runtime_error("STEP model is empty.");
        BRepMesh_IncrementalMesh mesher(shape,tolerance,Standard_False,.5,Standard_True);
        if(!mesher.IsDone())throw std::runtime_error("STEP tessellation failed.");
        std::vector<std::array<gp_Pnt,3>> triangles;
        for(TopExp_Explorer faces(shape,TopAbs_FACE);faces.More();faces.Next()) {
            const TopoDS_Face face=TopoDS::Face(faces.Current());TopLoc_Location location;
            const Handle(Poly_Triangulation) mesh=BRep_Tool::Triangulation(face,location);
            if(mesh.IsNull())throw std::runtime_error("A STEP face could not be triangulated.");
            if(triangles.size()+mesh->NbTriangles()>250000)
                throw std::runtime_error("STEP tessellation exceeds 250000 triangles; simplify the model.");
            const gp_Trsf transform=location.Transformation();
            for(int i=1;i<=mesh->NbTriangles();++i) {
                int a,b,c;mesh->Triangle(i).Get(a,b,c);
                if(face.Orientation()==TopAbs_REVERSED)std::swap(b,c);
                std::array<gp_Pnt,3> triangle={mesh->Node(a).Transformed(transform),mesh->Node(b).Transformed(transform),mesh->Node(c).Transformed(transform)};
                for(const gp_Pnt& p:triangle)if(!std::isfinite(p.X())||!std::isfinite(p.Y())||!std::isfinite(p.Z()))
                    throw std::runtime_error("STEP contains nonfinite coordinates.");
                triangles.push_back(triangle);
            }
        }
        if(triangles.empty())throw std::runtime_error("STEP model has no triangles.");
        std::ofstream out(argv[2],std::ios::binary|std::ios::trunc);
        if(!out)throw std::runtime_error("Cannot create STEP mesh output.");
        char header[80]={};std::memcpy(header,"149 native STEP mesh",20);out.write(header,80);write32(out,uint32_t(triangles.size()));
        for(const auto& triangle:triangles) {
            writeFloat(out,0);writeFloat(out,0);writeFloat(out,0);
            for(const gp_Pnt& p:triangle){writeFloat(out,float(p.X()));writeFloat(out,float(p.Y()));writeFloat(out,float(p.Z()));}
            const char attribute[2]={0,0};out.write(attribute,2);
        }
        out.close();if(!out)throw std::runtime_error("Cannot finish STEP mesh output.");
        return 0;
    } catch(const Standard_Failure& error) {
        std::cerr<<"STEP import failed: "<<error.GetMessageString()<<"\n";
    } catch(const std::exception& error) {
        std::cerr<<error.what()<<"\n";
    }
    return 1;
}
